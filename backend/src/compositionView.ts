import { marked } from "marked";
import { renderPrintPageHtml } from "./printView";

// 作文（compositions）の表示ロジック。admin.ts は db.ts を読み込むためテストから import できない。
// 状態判定・段落化・読書用ページの HTML 生成といった純粋な部分をここに置き、
// backend/test/compositionView.test.ts から検証する（printView.ts と同じ方針）。

function escapeHtml(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

/// Markdown由来の生HTMLタグ注入を防ぐため、パース前に `&`/`<`/`>` のみエスケープする
/// （admin.ts の renderMarkdown と同方針）。
export function renderCompositionMarkdown(value: string): string {
  if (!value.trim()) return "";
  const escaped = value.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
  return marked.parse(escaped, { async: false, breaks: true }) as string;
}

/// 学習者が入力した英文・意図を段落 HTML にする。空行で段落を分け、段落内の単一改行は
/// `<br>` として残す（学習者の改行位置は意図的なことがあるため潰さない）。
export function compositionParagraphsHtml(text: string): string {
  return text
    .replace(/\r\n?/g, "\n")
    .split(/\n[ \t]*\n+/)
    .map((paragraph) => paragraph.trim())
    .filter((paragraph) => paragraph.length > 0)
    .map((paragraph) => `<p>${escapeHtml(paragraph).replace(/\n/g, "<br>")}</p>`)
    .join("\n");
}

function normalize(value: string): string {
  return value.trim();
}

/// インライン <script> に埋め込む JSON（`</script>` での早期終了を防ぐ）
function jsonForScript(value: unknown): string {
  return JSON.stringify(value).replace(/</g, "\\u003c");
}

export interface CompositionDraft {
  englishText: string;
  japaneseText: string;
}

/// 状態バッジ（iOS の CompositionRow と同じ3状態）
/// - `draft`: まだ一度も添削していない
/// - `edited`: 添削済みだが下書きを直した（次の Review を送れる）
/// - `reviewed`: 下書きが最終ラウンドと同一（送る変更が無い）
export type CompositionStatusKind = "draft" | "edited" | "reviewed";

export interface CompositionStatusSource extends CompositionDraft {
  roundCount: number;
  lastRoundEnglishText: string | null;
  lastRoundJapaneseText: string | null;
}

/// 現在の下書きが最終ラウンドと同一か（＝新たに送る変更が無い）。
/// ラウンドがまだ無ければ false（初回は下書きさえあれば送れる）。
export function draftMatchesLastRound(source: CompositionStatusSource): boolean {
  if (source.roundCount === 0) return false;
  return (
    normalize(source.englishText) === normalize(source.lastRoundEnglishText ?? "") &&
    normalize(source.japaneseText) === normalize(source.lastRoundJapaneseText ?? "")
  );
}

export function compositionStatus(source: CompositionStatusSource): CompositionStatusKind {
  if (source.roundCount === 0) return "draft";
  return draftMatchesLastRound(source) ? "reviewed" : "edited";
}

/// Review を送れるか: 英日とも非空、かつ下書きが最終ラウンドと相違。
/// 画面のボタン活性と、POST 受け口のサーバ側ガードの両方で使う。
export function canReviewComposition(source: CompositionStatusSource): boolean {
  if (!normalize(source.englishText) || !normalize(source.japaneseText)) return false;
  return !draftMatchesLastRound(source);
}

/// 一覧・タイトルに出す1行プレビュー（英文優先、空なら意図）。超過分は…で切る。
export function compositionPreview(draft: CompositionDraft, max = 60): string {
  const source = normalize(draft.englishText) || normalize(draft.japaneseText);
  const oneLine = source.replace(/\s+/g, " ");
  if (!oneLine) return "";
  return oneLine.length > max ? `${oneLine.slice(0, max)}…` : oneLine;
}

// 紙に文字を書く感覚に寄せた執筆画面のパレット。読書用ページ（白地・serif）と地続きにする。
const PAPER_BG = "#EDE9DF"; // 机の色（紙の外側）
const PAPER_SHEET = "#FFFDF7"; // 紙そのもの
const PAPER_RULE = "#DFDACB"; // 横罫線
const PAPER_MARGIN_RULE = "rgba(186,120,110,0.30)"; // 縦の余白線（ノートの赤線）
const PAPER_INK = "#1F1B16"; // インク
const PAPER_FAINT = "#8C8578";
// 本文の行送り。罫線はこの間隔で引くので、両者を必ず同じ値から組み立てる（ズレると罫線から字が浮く）。
const PAPER_LINE_HEIGHT_PX = 34;

export interface CompositionChatMessageView {
  role: "user" | "assistant";
  /// 発言の生テキスト（user はエスケープして改行を保ち、assistant は Markdown として描画する）
  content: string;
}

export interface CompositionEditorPage {
  id: number;
  /// 現在の本文（textarea の初期値）
  text: string;
  /// 自動保存の POST 先
  saveUrl: string;
  /// 削除フォームの POST 先
  deleteUrl: string;
  /// チャット送信の POST 先
  chatUrl: string;
  /// ツールバーの戻り先
  backHref: string;
  /// これまでのチャット（古い順）
  messages: CompositionChatMessageView[];
  /// チャット欄に出すモデル名
  chatModel: string;
}

/// チャット1件分の吹き出し。assistant は Markdown、user は素のテキスト（改行は CSS の
/// white-space: pre-wrap で保つ）。クライアント側で追加する吹き出しも同じ構造にする。
export function chatMessageHtml(message: CompositionChatMessageView): string {
  const body =
    message.role === "assistant"
      ? renderCompositionMarkdown(message.content)
      : `<p class="plain">${escapeHtml(message.content)}</p>`;
  return `<div class="msg msg-${message.role}"><div class="bubble">${body}</div></div>`;
}

/// 執筆画面（/admin/writing/:id）の HTML。左に机の上の罫線紙、右に AI との相談チャットを置く
/// 2ペイン構成で、管理画面のダークテーマ・サイドバーは使わない単独ページ。
/// 本文は自動保存し、チャットの質問には常に「いま書かれている英文」がプロンプトへ含まれる。
export function renderCompositionEditorPageHtml(page: CompositionEditorPage): string {
  const lh = PAPER_LINE_HEIGHT_PX;
  const log = page.messages.map(chatMessageHtml).join("\n");
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>作文 #${page.id}</title>
  <style>
    :root { color-scheme: light; }
    * { box-sizing: border-box; }
    /* 左に紙、右にチャットの2ペイン。ページ全体はスクロールせず、各ペインが個別にスクロールする
       （書いている場所と会話の位置が互いにずれないようにするため）。 */
    body {
      margin: 0; background: ${PAPER_BG}; color: ${PAPER_INK};
      font-family: -apple-system, BlinkMacSystemFont, "Hiragino Sans", "Segoe UI", sans-serif;
      height: 100dvh; overflow: hidden; display: flex; flex-direction: column;
    }
    .split { flex: 1; min-height: 0; display: grid; grid-template-columns: minmax(0, 1fr) 420px; }
    .paper-pane { min-width: 0; overflow-y: auto; }
    /* 書く面積を最優先にした細いバー（高さ約 36px） */
    .toolbar {
      display: flex; align-items: center; gap: 14px; padding: 4px 16px;
      background: rgba(255,253,247,0.85); border-bottom: 1px solid #D9D3C5;
      font-size: 12.5px; backdrop-filter: blur(6px); flex: none;
    }
    .toolbar a { color: #1F6FEB; text-decoration: none; }
    .toolbar a:hover { text-decoration: underline; }
    .toolbar .spacer { flex: 1; }
    .toolbar .status { color: ${PAPER_FAINT}; font-size: 11.5px; }
    .toolbar form { margin: 0; display: flex; }
    .toolbar button {
      font: inherit; font-size: 12px; padding: 3px 11px; min-height: 28px; border-radius: 5px;
      background: transparent; color: #A3392F; border: 1px solid rgba(163,57,47,0.35); cursor: pointer;
    }
    .toolbar button:hover { background: rgba(163,57,47,0.07); }
    /* 机の上に置いた1枚の罫線紙。影で紙らしく浮かせ、罫線は紙の端から端まで引く。
       上下の padding を行送りの倍数にしてあるので、罫線と本文の行がぴったり重なる。
       縦の余白線はノートらしさのため、本文の左端から 12px 手前に引く。 */
    .sheet {
      --pad-x: 56px;
      max-width: 44em; margin: 28px auto 64px; background-color: ${PAPER_SHEET};
      box-shadow: 0 1px 2px rgba(60,50,35,0.10), 0 10px 30px rgba(60,50,35,0.12);
      padding: ${lh}px var(--pad-x) ${lh * 2}px;
      background-image:
        linear-gradient(
          to right,
          transparent calc(var(--pad-x) - 12px), ${PAPER_MARGIN_RULE} calc(var(--pad-x) - 12px),
          ${PAPER_MARGIN_RULE} calc(var(--pad-x) - 11px), transparent calc(var(--pad-x) - 11px)
        ),
        repeating-linear-gradient(
          to bottom,
          transparent 0, transparent ${lh - 1}px, ${PAPER_RULE} ${lh - 1}px, ${PAPER_RULE} ${lh}px
        );
    }
    /* 本文入力欄は紙の上の透明な層。行送りは罫線の間隔と同じ値でなければならない。
       padding は 0（罫線と字のズレを防ぐ）にして余白は .sheet 側で持つ。 */
    .paper {
      display: block; width: 100%; border: none; outline: none; resize: none; overflow: hidden;
      background: transparent; color: ${PAPER_INK};
      font-family: "Iowan Old Style", Georgia, "Hiragino Mincho ProN", "Yu Mincho", "Times New Roman", serif;
      font-size: 19px; line-height: ${lh}px; padding: 0; margin: 0;
      min-height: calc(100vh - 260px); caret-color: ${PAPER_INK};
    }
    .paper::placeholder { color: #B8B0A0; }

    /* 右ペイン: 書いている英文について相談するチャット（ChatGPT 風に上が履歴、下が入力欄） */
    .chat-pane {
      display: flex; flex-direction: column; min-height: 0;
      background: #F6F2E9; border-left: 1px solid #D9D3C5;
    }
    .chat-head {
      flex: none; padding: 12px 18px; border-bottom: 1px solid #E4DDCE;
      font-size: 13px; font-weight: 600; display: flex; align-items: baseline; gap: 8px;
    }
    .chat-head .model { font-weight: 400; font-size: 11.5px; color: ${PAPER_FAINT}; }
    .chat-log { flex: 1; min-height: 0; overflow-y: auto; padding: 18px; }
    .chat-empty { color: ${PAPER_FAINT}; font-size: 13px; line-height: 1.8; }
    .chat-empty code { background: #EDE7DA; padding: 1px 5px; border-radius: 4px; font-size: 12px; }
    .msg { display: flex; margin-bottom: 14px; }
    .msg-user { justify-content: flex-end; }
    .msg .bubble { max-width: 92%; font-size: 14px; line-height: 1.75; }
    .msg-user .bubble {
      background: #E7E0CF; border: 1px solid #DDD5C1; border-radius: 14px 14px 4px 14px; padding: 9px 13px;
    }
    .msg-assistant .bubble {
      background: ${PAPER_SHEET}; border: 1px solid #E4DDCE; border-radius: 14px 14px 14px 4px;
      padding: 11px 14px; box-shadow: 0 1px 2px rgba(60,50,35,0.05);
    }
    .msg .bubble p { margin: 0 0 0.7em; }
    .msg .bubble p.plain { white-space: pre-wrap; }
    .msg .bubble > *:last-child { margin-bottom: 0; }
    .msg .bubble ul, .msg .bubble ol { margin: 0 0 0.7em; padding-left: 1.3em; }
    .msg .bubble li { margin-bottom: 0.2em; }
    .msg .bubble code { background: #EFE9DC; padding: 1px 5px; border-radius: 4px; font-size: 0.92em; }
    .msg .bubble pre { background: #EFE9DC; padding: 10px 12px; border-radius: 8px; overflow-x: auto; }
    .msg .bubble pre code { background: none; padding: 0; }
    .msg .bubble h1, .msg .bubble h2, .msg .bubble h3 { font-size: 1.05em; margin: 0.6em 0 0.3em; }
    .msg.pending .bubble { color: ${PAPER_FAINT}; }
    .chat-error { color: #A3392F; font-size: 13px; margin-bottom: 14px; }
    .composer {
      flex: none; border-top: 1px solid #E4DDCE; padding: 12px; display: flex; gap: 8px; align-items: flex-end;
      background: #F6F2E9;
    }
    /* iOS Safari の自動ズームを避けるため 16px 以上 */
    .composer textarea {
      flex: 1; min-height: 44px; max-height: 40vh; resize: none; font: inherit; font-size: 16px; line-height: 1.6;
      background: ${PAPER_SHEET}; color: ${PAPER_INK}; border: 1px solid #DDD5C1; border-radius: 10px;
      padding: 11px 12px;
    }
    .composer textarea:focus { outline: none; border-color: #B9AF97; }
    .composer button {
      font: inherit; font-size: 13px; font-weight: 600; min-height: 44px; padding: 0 16px; border-radius: 10px;
      background: #3A3428; color: #FFFDF7; border: none; cursor: pointer;
    }
    .composer button:disabled { opacity: 0.4; cursor: not-allowed; }

    /* 狭い画面では紙の下にチャットを積む（ページ全体のスクロールに戻す）。
       紙は書いた分だけ伸びるので、初期の丈は抑えてチャットまですぐ届くようにする。 */
    @media (max-width: 900px) {
      body { height: auto; overflow: visible; }
      .split { grid-template-columns: 1fr; }
      .chat-pane { border-left: none; border-top: 1px solid #D9D3C5; height: 80vh; }
      .paper-pane { overflow: visible; }
      .paper { min-height: ${lh * 8}px; }
    }
    @media (max-width: 720px) {
      .sheet { --pad-x: 22px; margin: 0; box-shadow: none; }
    }
    @media print {
      body { background: #fff; height: auto; overflow: visible; display: block; }
      .toolbar, .chat-pane { display: none; }
      .split { display: block; }
      .paper-pane { overflow: visible; }
      .sheet { margin: 0; padding: 0; box-shadow: none; max-width: none; background-image: none; }
      .paper { font-size: 12pt; min-height: 0; }
    }
  </style>
</head>
<body>
  <div class="toolbar">
    <a href="${escapeHtml(page.backHref)}">← 作文一覧</a>
    <span class="spacer"></span>
    <span class="status" id="save-status">保存済み</span>
    <form method="post" action="${escapeHtml(page.deleteUrl)}"
          onsubmit="return confirm('この作文を削除します。よろしいですか？')">
      <button type="submit">削除</button>
    </form>
  </div>
  <div class="split">
    <div class="paper-pane">
      <div class="sheet">
        <textarea id="body" class="paper" spellcheck="true" autofocus
                  placeholder="ここに書く">${escapeHtml(page.text)}</textarea>
      </div>
    </div>
    <aside class="chat-pane">
      <div class="chat-head">AI に相談<span class="model">${escapeHtml(page.chatModel)}</span></div>
      <div class="chat-log" id="chat-log">
        ${
          log ||
          `<p class="chat-empty">左に書いている英文について質問できます。<br>
             例: <code>この文は自然ですか？</code> <code>ここは過去形で合っていますか？</code>
             <code>もっと自然な言い方は？</code></p>`
        }
      </div>
      <form class="composer" id="chat-form">
        <textarea id="chat-input" rows="1" placeholder="英文について質問する（⏎ で送信）"></textarea>
        <button type="submit" id="chat-send">送信</button>
      </form>
    </aside>
  </div>
  <script>
    (function () {
      var saveUrl = ${jsonForScript(page.saveUrl)};
      var chatUrl = ${jsonForScript(page.chatUrl)};
      var input = document.getElementById('body');
      var status = document.getElementById('save-status');
      var timer = null;
      var dirty = false;

      // 紙が書いた分だけ伸びるように高さを内容に合わせる。行送りの倍数に丸め、
      // 最終行の下にも罫線が続いて見えるようにする。
      function autogrow() {
        input.style.height = 'auto';
        var lines = Math.ceil(input.scrollHeight / ${lh});
        input.style.height = (lines * ${lh}) + 'px';
      }

      // 保存完了を待てるよう Promise を返す（チャット送信前に本文を確定させるため）
      function save() {
        if (!dirty) return Promise.resolve();
        clearTimeout(timer);
        dirty = false;
        status.textContent = '保存中…';
        return fetch(saveUrl, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ englishText: input.value })
        }).then(function (res) {
          if (!res.ok) throw new Error('save failed');
          status.textContent = '保存済み';
        }).catch(function () {
          dirty = true;
          status.textContent = '保存に失敗しました';
        });
      }

      // 入力停止 1.5 秒 + フォーカスを外したときに自動保存する
      input.addEventListener('input', function () {
        autogrow();
        dirty = true;
        status.textContent = '未保存';
        clearTimeout(timer);
        timer = setTimeout(save, 1500);
      });
      input.addEventListener('blur', save);

      document.addEventListener('keydown', function (event) {
        if ((event.metaKey || event.ctrlKey) && event.key === 's') {
          event.preventDefault();
          save();
        }
      });

      // 自動保存前に閉じようとしたら引き止める
      window.addEventListener('beforeunload', function (event) {
        if (dirty) { event.preventDefault(); event.returnValue = ''; }
      });

      autogrow();
      // カーソルを末尾に置いて続きから書けるようにする
      input.setSelectionRange(input.value.length, input.value.length);

      // --- AI との相談チャット ---------------------------------------------
      var log = document.getElementById('chat-log');
      var form = document.getElementById('chat-form');
      var question = document.getElementById('chat-input');
      var send = document.getElementById('chat-send');
      var sending = false;

      function scrollLog() { log.scrollTop = log.scrollHeight; }

      /// 吹き出しを1件足す。html=false のときは textContent として入れる（ユーザー入力用）
      function appendMessage(role, body, isHtml, extraClass) {
        var empty = log.querySelector('.chat-empty');
        if (empty) empty.remove();
        var wrap = document.createElement('div');
        wrap.className = 'msg msg-' + role + (extraClass ? ' ' + extraClass : '');
        var bubble = document.createElement('div');
        bubble.className = 'bubble';
        if (isHtml) {
          bubble.innerHTML = body;
        } else {
          var p = document.createElement('p');
          p.className = 'plain';
          p.textContent = body;
          bubble.appendChild(p);
        }
        wrap.appendChild(bubble);
        log.appendChild(wrap);
        scrollLog();
        return wrap;
      }

      function ask() {
        var text = question.value.trim();
        if (!text || sending) return;
        sending = true;
        send.disabled = true;
        question.value = '';
        question.style.height = 'auto';
        appendMessage('user', text, false);
        var pending = appendMessage('assistant', '考え中…', false, 'pending');

        // 質問には「いま書かれている英文」が同梱されるので、先に本文の保存を確定させる
        save().then(function () {
          return fetch(chatUrl, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ message: text })
          });
        }).then(function (res) {
          return res.json().then(function (data) {
            if (!res.ok) throw new Error(data.error || 'chat failed');
            return data;
          });
        }).then(function (data) {
          pending.classList.remove('pending');
          pending.querySelector('.bubble').innerHTML = data.replyHtml;
          scrollLog();
        }).catch(function (error) {
          pending.remove();
          var note = document.createElement('p');
          note.className = 'chat-error';
          note.textContent = '返答を取得できませんでした: ' + error.message;
          log.appendChild(note);
          question.value = text;
          scrollLog();
        }).finally(function () {
          sending = false;
          send.disabled = false;
        });
      }

      form.addEventListener('submit', function (event) {
        event.preventDefault();
        ask();
      });

      // ⏎ で送信、⇧⏎ で改行（ChatGPT と同じ操作感）
      question.addEventListener('keydown', function (event) {
        if (event.key === 'Enter' && !event.shiftKey && !event.isComposing) {
          event.preventDefault();
          ask();
        }
      });
      question.addEventListener('input', function () {
        question.style.height = 'auto';
        question.style.height = Math.min(question.scrollHeight, window.innerHeight * 0.4) + 'px';
      });

      scrollLog();
    })();
  </script>
</body>
</html>`;
}

export interface CompositionReadRound {
  roundIndex: number;
  englishText: string;
  japaneseText: string;
  correctedText: string;
  explanation: string;
  /// 表示用に整形済みの日時文字列
  createdAt: string;
}

export interface CompositionReadPage {
  id: number;
  /// 見出し兼 <title>（呼び出し側で作文プレビューから作る）
  title: string;
  /// 見出し下の補足行（ID・更新日時・ラウンド数など）
  meta: string;
  /// 未添削のときに表示する現在の下書き
  draft: CompositionDraft;
  /// 添削ラウンド（古い順）
  rounds: CompositionReadRound[];
  backHref: string;
}

// 読み物として通しで読むための本文スタイル（plan Step 3-1 / 3-2）。
// printView の白地・serif を土台に、行長を 68ch に抑え、
// 「You wrote / Corrected」を PC では 2 カラム、狭い画面では縦積みにする。
const READ_STYLE = `
  article {
    max-width: 72ch;
    font-family: "Iowan Old Style", Georgia, "Hiragino Mincho ProN", "Yu Mincho", "Times New Roman", serif;
  }
  .body p, .body li { font-size: clamp(17px, 0.6vw + 15px, 20px); line-height: 1.9; }
  .body .final p { text-align: justify; }
  .lead-label {
    font-family: -apple-system, BlinkMacSystemFont, "Hiragino Sans", "Segoe UI", sans-serif;
    font-size: 11px; letter-spacing: 0.12em; text-transform: uppercase; color: #6B7280;
    margin: 0 0 6px; font-weight: 600;
  }
  .intent { color: #374151; }
  .intent p { font-size: 15px; line-height: 1.8; text-align: left; }
  .round { border-top: 1px solid #E5E7EB; margin-top: 40px; padding-top: 24px; }
  .round-head {
    font-family: -apple-system, BlinkMacSystemFont, "Hiragino Sans", "Segoe UI", sans-serif;
    font-size: 12px; color: #6B7280; margin: 0 0 16px;
    display: flex; justify-content: space-between; gap: 12px; flex-wrap: wrap;
  }
  .compare { display: grid; grid-template-columns: 1fr 1fr; gap: 24px; }
  .compare p { font-size: 16px; line-height: 1.8; text-align: left; }
  .compare .corrected p { color: #111; }
  .compare .wrote p { color: #6B7280; }
  .explanation { margin-top: 20px; }
  .explanation p, .explanation li { font-size: 15px; line-height: 1.8; text-align: left; }
  .no-rounds { color: #6B7280; font-style: italic; }
  @media (max-width: 720px) {
    .compare { grid-template-columns: 1fr; gap: 16px; }
    article { padding: 24px 20px 48px; }
  }
  @media print {
    /* 基底スタイルの @media print より後ろに置かれるため、紙面いっぱいの指定をここで復元する */
    article { max-width: none; padding: 0; }
    .compare { grid-template-columns: 1fr 1fr; }
    .body p, .body li { font-size: 12pt; }
    .compare p, .explanation p, .explanation li, .intent p { font-size: 10.5pt; }
  }
`;

function readRoundHtml(round: CompositionReadRound): string {
  const explanation = renderCompositionMarkdown(round.explanation);
  return `
    <section class="round">
      <div class="round-head"><span>Round ${round.roundIndex}</span><span>${escapeHtml(round.createdAt)}</span></div>
      <div class="compare">
        <div class="wrote">
          <p class="lead-label">You wrote</p>
          ${compositionParagraphsHtml(round.englishText)}
        </div>
        <div class="corrected">
          <p class="lead-label">Corrected</p>
          ${compositionParagraphsHtml(round.correctedText)}
        </div>
      </div>
      ${explanation ? `<div class="explanation"><p class="lead-label">Explanation</p>${explanation}</div>` : ""}
    </section>
  `;
}

/// 読書用ページ（/admin/writing/:id/read）の HTML。最終的な添削済み英文を先頭に大きく置き、
/// その下に各ラウンドの対比と解説を古い順に並べる。管理画面のダークテーマは使わず
/// printView と同じ単独ページとして描画するので、そのまま印刷にも使える。
export function renderCompositionReadPageHtml(page: CompositionReadPage): string {
  const lastRound = page.rounds.at(-1);
  const finalText = lastRound?.correctedText ?? page.draft.englishText;
  const intentText = lastRound?.japaneseText ?? page.draft.japaneseText;

  const finalHtml = compositionParagraphsHtml(finalText);
  const intentHtml = compositionParagraphsHtml(intentText);

  const bodyHtml = `
    <section class="final">
      ${finalHtml || '<p class="no-rounds">(本文がまだありません)</p>'}
    </section>
    ${intentHtml ? `<section class="intent"><p class="lead-label">伝えたかった意図</p>${intentHtml}</section>` : ""}
    ${page.rounds.length === 0 ? '<p class="no-rounds">この作文はまだ添削されていません。</p>' : ""}
    ${page.rounds.map(readRoundHtml).join("\n")}
  `;

  return renderPrintPageHtml({
    lang: "en",
    title: page.title,
    meta: page.meta,
    bodyHtml,
    backHref: page.backHref,
    backLabel: "← 編集画面に戻る",
    extraStyle: READ_STYLE,
  });
}
