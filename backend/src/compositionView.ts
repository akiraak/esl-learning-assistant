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

/// 一覧・読書ページの見出し。タイトルが入っていればそれを、空欄なら従来どおり
/// 本文の先頭（無ければ意図）から作る（docs/plans/composition-title.md）。
export function compositionListTitle(source: CompositionDraft & { title: string }, max = 70): string {
  const title = normalize(source.title).replace(/\s+/g, " ");
  if (title) return title.length > max ? `${title.slice(0, max)}…` : title;
  return compositionPreview(source, max);
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

/// 綴り誤りの位置（spellcheck.ts の Misspelling と同じ形。表示側が判定モジュールに依存しないよう
/// ここでも定義しておく）。start/end は本文の文字オフセットで、終端は排他。
export interface EditorMisspelling {
  start: number;
  end: number;
  word: string;
}

export interface CompositionEditorPage {
  id: number;
  /// 現在のタイトル（空欄可。空なら一覧では本文の先頭が見出しになる）
  title: string;
  /// タイトル入力欄の maxlength（compositionTitle.ts の上限を呼び出し側から渡す）
  titleMaxLength: number;
  /// 「本文から生成」の POST 先
  titleUrl: string;
  /// 現在の本文（textarea の初期値）
  text: string;
  /// 自動保存の POST 先（本文とタイトルを一緒に送る）
  saveUrl: string;
  /// 綴り検査の POST 先
  spellcheckUrl: string;
  /// 修正候補の POST 先（赤い語にカーソルを置いたときに 1 語だけ問い合わせる）
  spellSuggestUrl: string;
  /// 「辞書に追加」の POST 先
  spellIgnoreUrl: string;
  /// 開いた時点の綴り誤り（初期表示から赤線が出ている状態にする）
  misspellings: EditorMisspelling[];
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

/// 紙と AI 欄の仕切りのつまみに描く左右の矢印（CSS の url() へ直接埋める data URI 用）。
/// 外部ファイルを増やさずに済むよう SVG をそのまま持ち、CSS で壊れる文字だけ退避する。
function resizeGripSvg(): string {
  const svg =
    '<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10" viewBox="0 0 10 10" ' +
    'fill="none" stroke="#4E4636" stroke-width="1.3" stroke-linecap="round" stroke-linejoin="round">' +
    '<path d="M4 2 1.5 5 4 8"/><path d="M6 2 8.5 5 6 8"/></svg>';
  return encodeURIComponent(svg);
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
    /* 右の AI 欄の幅は仕切りのドラッグで変わる。既定値はここ、実際の値は script が
       --chat-w を書き換えて反映する（localStorage に覚えた幅を復元する）。 */
    .split {
      flex: 1; min-height: 0; display: grid;
      --chat-w: 420px;
      grid-template-columns: minmax(0, 1fr) 6px var(--chat-w);
    }
    /* 紙の左右余白（--pad-x）は紙の外に置くタイトル行とも揃えたいので、ペイン側で持つ。 */
    .paper-pane { min-width: 0; overflow-y: auto; --pad-x: 56px; }
    /* 紙と AI 欄の間の細い仕切り。掴む余地を持たせるため見た目の線より当たり判定を広くする。 */
    .resizer {
      position: relative; cursor: col-resize; background: #E4DDCE;
      border-left: 1px solid #D9D3C5; border-right: 1px solid #D9D3C5;
      touch-action: none;
    }
    .resizer::before {
      content: ''; position: absolute; top: 0; bottom: 0; left: -4px; right: -4px;
    }
    /* 掴んで左右に動かせることが一目で分かるよう、中ほどに縦長のつまみ（左右向きの矢印付き）を置く。
       つまみは仕切りより幅広なので、はみ出した分は両側の面へ少し重なる。 */
    .resizer::after {
      content: ''; position: absolute; top: 50%; left: 50%; transform: translate(-50%, -50%);
      width: 14px; height: 56px; border-radius: 7px;
      background-color: #D3C9B2; border: 1px solid #C2B79C;
      box-shadow: 0 1px 2px rgba(60,50,35,0.12);
      background-repeat: no-repeat; background-position: center;
      background-image: url("data:image/svg+xml,${resizeGripSvg()}");
    }
    .resizer:hover::after, .resizer:focus-visible::after, .resizer.dragging::after {
      background-color: #C0B394; border-color: #A99C7E;
    }
    .resizer:focus-visible { outline: none; }
    .resizer:hover, .resizer:focus-visible, .resizer.dragging { background: #D9CFB8; }
    /* ドラッグ中に本文が選択されてしまうのを止める */
    body.resizing { cursor: col-resize; user-select: none; }
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
    /* 机の上に置いた1枚の罫線紙。書ける幅を最優先にペイン幅いっぱいへ広げ、
       紙の縁が窓の縁に貼り付かないよう左右に少しだけ余白を残す。
       影で紙らしく浮かせ、罫線は紙の端から端まで引く。
       上下の padding を行送りの倍数にしてあるので、罫線と本文の行がぴったり重なる。
       縦の余白線はノートらしさのため、本文の左端から 12px 手前に引く。 */
    .sheet {
      position: relative;
      margin: 0 24px 64px; background-color: ${PAPER_SHEET};
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
    /* 記事タイトルは本文の紙とは別物なので、罫線紙の上にもう一枚の紙（表紙）として置く。
       紙と同じ地色・同じ左右の位置（外 24px + --pad-x）にして、影だけで本文の紙と分ける。
       影は本文の紙より浅くし、小さい紙が薄く浮いて見えるようにする。 */
    .title-row {
      display: flex; align-items: center; gap: 12px;
      margin: 24px 24px 12px; padding: 14px var(--pad-x);
      background-color: ${PAPER_SHEET};
      box-shadow: 0 1px 2px rgba(60,50,35,0.10), 0 6px 18px rgba(60,50,35,0.10);
    }
    .title-input {
      flex: 1; min-width: 0; padding: 2px 0; margin: 0;
      border: none; border-bottom: 1px solid transparent;
      background: transparent; outline: none; color: ${PAPER_INK};
      font-family: "Iowan Old Style", Georgia, "Hiragino Mincho ProN", "Yu Mincho", "Times New Roman", serif;
      font-size: 26px; line-height: 1.3;
    }
    .title-input:hover { border-bottom-color: #DDD5C1; }
    .title-input:focus { border-bottom-color: #C2B79C; }
    .title-input::placeholder { color: #BDB5A5; font-size: 15px; }
    .title-gen {
      flex: none; font-family: inherit; font-size: 12px; line-height: 1; padding: 6px 10px;
      border-radius: 6px; cursor: pointer;
      background: #F0EADC; color: #5C5445; border: 1px solid #DDD5C1;
    }
    .title-gen:hover { background: #E7E0CF; color: ${PAPER_INK}; }
    .title-gen:disabled { opacity: 0.5; cursor: not-allowed; }
    /* 本文入力欄と下敷きの共通の親。下敷きはここを基準に重ねるので、
       紙の外側の作りが変わっても赤線が字の下からずれない。 */
    .paper-area { position: relative; }
    /* 本文入力欄と、その背後に敷く綴り検査の下敷き。折り返し位置が 1px でも違うと
       赤線が字の下から外れるので、字組みに関わる指定は必ずこの 1 か所で両方に当てる。 */
    .paper, .paper-backdrop {
      font-family: "Iowan Old Style", Georgia, "Hiragino Mincho ProN", "Yu Mincho", "Times New Roman", serif;
      font-size: 19px; line-height: ${lh}px; padding: 0; margin: 0; border: none;
      white-space: pre-wrap; word-wrap: break-word; overflow-wrap: break-word;
      text-align: left; letter-spacing: normal;
    }
    /* 本文入力欄は紙の上の透明な層。行送りは罫線の間隔と同じ値でなければならない。
       padding は 0（罫線と字のズレを防ぐ）にして余白は .sheet 側で持つ。 */
    .paper {
      position: relative; z-index: 1;
      display: block; width: 100%; outline: none; resize: none; overflow: hidden;
      background: transparent; color: ${PAPER_INK};
      min-height: calc(100vh - 260px); caret-color: ${PAPER_INK};
    }
    .paper::placeholder { color: #B8B0A0; }
    /* 本文と同じ字を透明で敷き直し、綴りの誤りにだけ赤い波線を引く層。
       本文入力欄と同じ親（.paper-area）にぴったり重ねるので、座標がそのまま一致する。
       textarea はオートグローで内容の丈まで伸びるためスクロール位置の同期は要らない。 */
    .paper-backdrop {
      position: absolute; top: 0; left: 0; right: 0;
      color: transparent; pointer-events: none; user-select: none; overflow: hidden;
    }
    /* 紙にペンで引いた印に寄せる（標準の赤い波線は spellcheck="false" で止めてある） */
    .paper-backdrop mark {
      background: none; color: transparent;
      text-decoration: underline wavy;
      text-decoration-color: rgba(163,57,47,0.75);
      text-decoration-skip-ink: none;
    }

    /* 赤い語にカーソルを置いたときに出る小さな紙片。修正候補と「辞書に追加」を置く。
       紙の上に浮かせるので z-index は本文入力欄より上。 */
    .spell-pop {
      position: fixed; z-index: 5; display: none;
      background: ${PAPER_SHEET}; border: 1px solid #DDD5C1; border-radius: 8px;
      box-shadow: 0 2px 4px rgba(60,50,35,0.10), 0 8px 20px rgba(60,50,35,0.16);
      padding: 4px; min-width: 132px; max-width: 240px;
      font-family: -apple-system, BlinkMacSystemFont, "Hiragino Sans", "Segoe UI", sans-serif;
    }
    .spell-pop.open { display: block; }
    .spell-pop button {
      display: block; width: 100%; text-align: left; font: inherit; font-size: 13px;
      padding: 6px 10px; border: none; border-radius: 5px; background: transparent;
      color: ${PAPER_INK}; cursor: pointer;
    }
    .spell-pop button:hover { background: #F0EADC; }
    .spell-pop .none { padding: 6px 10px; font-size: 12.5px; color: ${PAPER_FAINT}; }
    .spell-pop .sep { border-top: 1px solid #E9E2D2; margin: 4px 0; }
    .spell-pop .ignore { color: ${PAPER_FAINT}; font-size: 12px; }

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
    /* AI がコードフェンスで囲んだ英文は「そのまま紙へ写せるまとまり」。等幅のコード塊ではなく、
       本文と同じ serif の英文カードとして見せ、右上にコピーボタンを重ねる。 */
    .msg .bubble pre, .msg .bubble blockquote {
      position: relative; margin: 0 0 0.7em; background: #FFFDF7;
      border: 1px solid #E4DDCE; border-left: 3px solid #C9BFA6; border-radius: 8px;
      padding: 10px 12px; padding-right: 62px; overflow-x: auto;
      font-family: "Iowan Old Style", Georgia, "Times New Roman", serif;
      font-size: 14.5px; line-height: 1.7; white-space: pre-wrap; word-break: break-word;
    }
    .msg .bubble blockquote > *:last-child { margin-bottom: 0; }
    .msg .bubble pre code { background: none; padding: 0; font: inherit; }
    /* カードの角に控えめに置き、押した直後だけ結果を出す */
    .copy-btn {
      position: absolute; top: 6px; right: 6px;
      font-family: -apple-system, BlinkMacSystemFont, "Hiragino Sans", "Segoe UI", sans-serif;
      font-size: 11.5px; line-height: 1; padding: 5px 8px; border-radius: 6px;
      background: #F0EADC; color: ${PAPER_FAINT}; border: 1px solid #DDD5C1; cursor: pointer;
    }
    .copy-btn:hover { background: #E7E0CF; color: ${PAPER_INK}; }
    .copy-btn.done { color: #3F6B4A; border-color: #BFD0BF; background: #E8F0E6; }
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
      .resizer { display: none; }
      .chat-pane { border-left: none; border-top: 1px solid #D9D3C5; height: 80vh; }
      .paper-pane { overflow: visible; }
      .paper { min-height: ${lh * 8}px; }
    }
    @media (max-width: 720px) {
      .paper-pane { --pad-x: 22px; }
      .sheet { margin: 0; box-shadow: none; }
      .title-row { margin: 0 0 8px; padding: 12px var(--pad-x); box-shadow: none; }
      .title-input { font-size: 22px; }
    }
    @media print {
      body { background: #fff; height: auto; overflow: visible; display: block; }
      .toolbar, .chat-pane, .resizer, .copy-btn, .title-gen { display: none; }
      .split { display: block; }
      .paper-pane { overflow: visible; }
      .sheet { margin: 0; padding: 0; box-shadow: none; max-width: none; background-image: none; }
      .title-row { margin: 0 0 10px; padding: 0; background: none; box-shadow: none; }
      .title-input { border-bottom: none; }
      .paper { font-size: 12pt; min-height: 0; }
      /* 印刷物に赤線は要らない */
      .paper-backdrop { display: none; }
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
      <div class="title-row">
        <input id="title" class="title-input" type="text" maxlength="${page.titleMaxLength}"
               placeholder="タイトル（空欄なら一覧に本文の先頭が出ます）"
               value="${escapeHtml(page.title)}">
        <button type="button" class="title-gen" id="title-generate">本文から生成</button>
      </div>
      <div class="sheet">
        <div class="paper-area">
          <div class="paper-backdrop" id="backdrop" aria-hidden="true"></div>
          <textarea id="body" class="paper" spellcheck="false" autofocus
                    placeholder="ここに書く">${escapeHtml(page.text)}</textarea>
        </div>
      </div>
      <div class="spell-pop" id="spell-pop"></div>
    </div>
    <div class="resizer" id="resizer" role="separator" aria-orientation="vertical"
         tabindex="0" title="ドラッグで幅を変える" aria-label="紙と AI 欄の境界"></div>
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
      var titleUrl = ${jsonForScript(page.titleUrl)};
      var input = document.getElementById('body');
      var titleInput = document.getElementById('title');
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
          body: JSON.stringify({ englishText: input.value, title: titleInput.value })
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

      // タイトルも本文と同じ自動保存に相乗りする（保存要求は 1 回にまとめる）
      function markDirty() {
        dirty = true;
        status.textContent = '未保存';
        clearTimeout(timer);
        timer = setTimeout(save, 1500);
      }
      titleInput.addEventListener('input', markDirty);
      titleInput.addEventListener('blur', save);
      // 題の途中で改行はできないので、⏎ は本文へ移る操作にする
      titleInput.addEventListener('keydown', function (event) {
        if (event.key === 'Enter' && !event.isComposing) {
          event.preventDefault();
          input.focus();
        }
      });

      // 「本文から生成」。本文を確定させてからサーバへ頼み、返ってきた題を欄へ入れる
      // （サーバ側でも保存済みだが、以後の編集と足並みを揃えるため保存経路を通し直す）。
      var titleButton = document.getElementById('title-generate');
      titleButton.addEventListener('click', function () {
        if (titleButton.disabled) return;
        titleButton.disabled = true;
        titleButton.textContent = '生成中…';
        save().then(function () {
          return fetch(titleUrl, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{}' });
        }).then(function (res) {
          return res.json().then(function (data) {
            if (!res.ok) throw new Error(data.error || 'title failed');
            return data;
          });
        }).then(function (data) {
          titleInput.value = data.title;
          dirty = true;
          save();
        }).catch(function (error) {
          status.textContent = 'タイトルを生成できませんでした: ' + error.message;
        }).finally(function () {
          titleButton.disabled = false;
          titleButton.textContent = '本文から生成';
        });
      });

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

      // --- 綴りの強調表示 ---------------------------------------------------
      var spellcheckUrl = ${jsonForScript(page.spellcheckUrl)};
      var backdrop = document.getElementById('backdrop');
      var spans = ${jsonForScript(page.misspellings)};
      // 入力中の語まで赤くすると打鍵のたびに赤線が明滅するので、打っている最中だけ
      // カーソルのある語を伏せる。カーソルを動かしただけのときは伏せない（Phase 3 の
      // ポップオーバーは、赤い語にカーソルを置いて開くため）。
      var typing = false;
      var spellTimer = null;

      /// 本文と同じ字を下敷きに敷き直し、spans の範囲だけ <mark> で包む。
      /// 本文は textContent として入れるので HTML としては解釈されない。
      function renderMarks() {
        var text = input.value;
        var caret = input.selectionStart;
        var fragment = document.createDocumentFragment();
        var cursor = 0;
        for (var i = 0; i < spans.length; i += 1) {
          var span = spans[i];
          if (span.start < cursor || span.end > text.length) continue;
          if (text.slice(span.start, span.end) !== span.word) continue;
          if (typing && caret >= span.start && caret <= span.end) continue;
          fragment.appendChild(document.createTextNode(text.slice(cursor, span.start)));
          var mark = document.createElement('mark');
          mark.dataset.index = String(i);
          mark.textContent = span.word;
          fragment.appendChild(mark);
          cursor = span.end;
        }
        // 末尾の改行が潰れて下の行がずれないよう、最後に空白を1つ足す
        fragment.appendChild(document.createTextNode(text.slice(cursor) + ' '));
        backdrop.replaceChildren(fragment);
      }

      /// 判定はサーバ側。返答待ちの間に打鍵が進んでいたらオフセットが食い違うので、
      /// 送った本文と現在の本文が一致するときだけ反映する（違えば次のデバウンスに任せる）。
      /// 通信に失敗したら直前の結果を残したまま黙って諦める（書く手を止めない）。
      function runSpellcheck() {
        var sent = input.value;
        fetch(spellcheckUrl, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ text: sent })
        }).then(function (res) {
          if (!res.ok) throw new Error('spellcheck failed');
          return res.json();
        }).then(function (data) {
          if (input.value !== sent) return;
          spans = data.misspellings || [];
          renderMarks();
        }).catch(function () {});
      }

      function scheduleSpellcheck() {
        clearTimeout(spellTimer);
        spellTimer = setTimeout(runSpellcheck, 600);
      }

      input.addEventListener('input', function () {
        typing = true;
        renderMarks();
        scheduleSpellcheck();
      });
      // カーソルが動いただけなら通信せずに描き直す（打ち終えた語がここで赤くなる）。
      // keyup は打鍵のたびにも来るので、カーソル移動キーに限る。
      var CARET_KEYS = [
        'ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown', 'Home', 'End', 'PageUp', 'PageDown'
      ];
      input.addEventListener('click', function () {
        typing = false;
        renderMarks();
        syncPopover();
      });
      input.addEventListener('keyup', function (event) {
        if (CARET_KEYS.indexOf(event.key) === -1) return;
        typing = false;
        renderMarks();
        syncPopover();
      });
      input.addEventListener('blur', function () {
        typing = false;
        renderMarks();
      });

      // --- 修正候補のポップオーバー -----------------------------------------
      var suggestUrl = ${jsonForScript(page.spellSuggestUrl)};
      var ignoreUrl = ${jsonForScript(page.spellIgnoreUrl)};
      var pop = document.getElementById('spell-pop');
      var popIndex = -1;

      function closePopover() {
        popIndex = -1;
        pop.classList.remove('open');
        pop.replaceChildren();
      }

      function popButton(label, className, onClick) {
        var button = document.createElement('button');
        button.type = 'button';
        button.textContent = label;
        if (className) button.className = className;
        // mousedown で拾う（click だと textarea から先にフォーカスが外れる）
        button.addEventListener('mousedown', function (event) {
          event.preventDefault();
          onClick();
        });
        return button;
      }

      /// 候補を選んだとき: 本文を置き換え、後続の語の位置をずらして描き直す。
      /// 判定し直しはサーバに任せる（置換で新しい誤りが生まれることもあるため）。
      function applySuggestion(index, replacement) {
        var span = spans[index];
        if (!span) return;
        var delta = replacement.length - (span.end - span.start);
        input.setRangeText(replacement, span.start, span.end, 'end');
        spans = spans.filter(function (item) { return item !== span; }).map(function (item) {
          return item.start >= span.end
            ? { start: item.start + delta, end: item.end + delta, word: item.word }
            : item;
        });
        closePopover();
        typing = false;
        renderMarks();
        autogrow();
        input.focus();
        dirty = true;
        status.textContent = '未保存';
        save();
        scheduleSpellcheck();
      }

      /// 「辞書に追加」: 以後どの作文でもこの語は赤くならない。
      /// 画面上も同じ綴りの語をまとめて消す（サーバの応答を待たずに消すと巻き戻しが要るので待つ）。
      function ignoreWord(index) {
        var span = spans[index];
        if (!span) return;
        var lower = span.word.toLowerCase();
        closePopover();
        input.focus();
        fetch(ignoreUrl, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ word: span.word })
        }).then(function (res) {
          if (!res.ok) throw new Error('ignore failed');
          spans = spans.filter(function (item) { return item.word.toLowerCase() !== lower; });
          renderMarks();
        }).catch(function () {});
      }

      function fillPopover(index, suggestions) {
        if (popIndex !== index) return;
        pop.replaceChildren();
        if (suggestions.length === 0) {
          var none = document.createElement('div');
          none.className = 'none';
          none.textContent = '候補なし';
          pop.appendChild(none);
        } else {
          suggestions.forEach(function (suggestion) {
            pop.appendChild(popButton(suggestion, '', function () {
              applySuggestion(index, suggestion);
            }));
          });
        }
        var sep = document.createElement('div');
        sep.className = 'sep';
        pop.appendChild(sep);
        pop.appendChild(popButton('辞書に追加', 'ignore', function () { ignoreWord(index); }));
      }

      /// カーソルのある赤い語の下にポップオーバーを開く（無ければ閉じる）。
      /// 位置は下敷きの <mark> の実寸から取るので、折り返しても語の真下に出る。
      function syncPopover() {
        var caret = input.selectionStart;
        var index = -1;
        for (var i = 0; i < spans.length; i += 1) {
          if (caret >= spans[i].start && caret <= spans[i].end) { index = i; break; }
        }
        if (index === -1) { closePopover(); return; }
        if (index === popIndex) return;

        var mark = backdrop.querySelector('mark[data-index="' + index + '"]');
        if (!mark) { closePopover(); return; }

        popIndex = index;
        pop.replaceChildren();
        var loading = document.createElement('div');
        loading.className = 'none';
        loading.textContent = '候補を探しています…';
        pop.appendChild(loading);
        pop.classList.add('open');
        var rect = mark.getBoundingClientRect();
        pop.style.top = (rect.bottom + 4) + 'px';
        pop.style.left = Math.min(rect.left, window.innerWidth - pop.offsetWidth - 8) + 'px';

        var word = spans[index].word;
        fetch(suggestUrl, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ word: word })
        }).then(function (res) {
          if (!res.ok) throw new Error('suggest failed');
          return res.json();
        }).then(function (data) {
          fillPopover(index, data.suggestions || []);
        }).catch(function () {
          fillPopover(index, []);
        });
      }

      // 書き続ける・別の場所を触る・紙をスクロールしたら閉じる（浮いたまま残さない）
      input.addEventListener('input', closePopover);
      document.addEventListener('keydown', function (event) {
        if (event.key === 'Escape') closePopover();
      });
      document.addEventListener('mousedown', function (event) {
        if (!pop.contains(event.target)) closePopover();
      });
      document.querySelector('.paper-pane').addEventListener('scroll', closePopover);
      window.addEventListener('resize', closePopover);

      renderMarks();

      // --- 紙と AI 欄の境界（ドラッグで幅を変え、ブラウザに覚えさせる） -------
      var split = document.querySelector('.split');
      var resizer = document.getElementById('resizer');
      var WIDTH_KEY = 'composition.chatWidth';
      var MIN_CHAT = 280;
      var MIN_PAPER = 360;

      // 画面が狭くなっても紙が潰れないよう、覚えた幅も含めて必ずここを通す
      function clampWidth(px) {
        var max = Math.max(MIN_CHAT, window.innerWidth - MIN_PAPER);
        return Math.round(Math.min(Math.max(px, MIN_CHAT), Math.min(720, max)));
      }

      function applyWidth(px) {
        split.style.setProperty('--chat-w', clampWidth(px) + 'px');
        // 幅が変わると本文の折り返しが変わるので、紙の丈を取り直す
        autogrow();
        closePopover();
      }

      function currentWidth() {
        return document.querySelector('.chat-pane').getBoundingClientRect().width;
      }

      try {
        var saved = parseFloat(localStorage.getItem(WIDTH_KEY) || '');
        if (saved > 0) split.style.setProperty('--chat-w', clampWidth(saved) + 'px');
      } catch (err) { /* localStorage が使えない環境では既定幅のまま */ }

      function remember(px) {
        try { localStorage.setItem(WIDTH_KEY, String(clampWidth(px))); } catch (err) {}
      }

      var dragWidth = 0;
      resizer.addEventListener('pointerdown', function (event) {
        event.preventDefault();
        resizer.setPointerCapture(event.pointerId);
        resizer.classList.add('dragging');
        document.body.classList.add('resizing');
        dragWidth = currentWidth();
      });
      resizer.addEventListener('pointermove', function (event) {
        if (!resizer.classList.contains('dragging')) return;
        // 右端からの距離がそのまま AI 欄の幅
        dragWidth = window.innerWidth - event.clientX;
        applyWidth(dragWidth);
      });
      function endDrag() {
        if (!resizer.classList.contains('dragging')) return;
        resizer.classList.remove('dragging');
        document.body.classList.remove('resizing');
        remember(dragWidth);
      }
      resizer.addEventListener('pointerup', endDrag);
      resizer.addEventListener('pointercancel', endDrag);

      // キーボードでも動かせるように（← で AI 欄を広げ、→ で紙を広げる）
      resizer.addEventListener('keydown', function (event) {
        var step = event.shiftKey ? 40 : 12;
        if (event.key === 'ArrowLeft') { event.preventDefault(); }
        else if (event.key === 'ArrowRight') { event.preventDefault(); step = -step; }
        else return;
        var next = currentWidth() + step;
        applyWidth(next);
        remember(next);
      });

      // ウィンドウが狭くなったときに覚えた幅がはみ出さないようにする
      window.addEventListener('resize', function () {
        // 縦積みのときは幅の指定が効かないので、覚えた値を上書きしないよう触らない
        if (window.matchMedia('(max-width: 900px)').matches) return;
        applyWidth(currentWidth());
      });

      // --- AI との相談チャット ---------------------------------------------
      var log = document.getElementById('chat-log');
      var form = document.getElementById('chat-form');
      var question = document.getElementById('chat-input');
      var send = document.getElementById('chat-send');
      var sending = false;

      function scrollLog() { log.scrollTop = log.scrollHeight; }

      // AI がコードフェンスで囲んだ英文（＋古い履歴の引用ブロック）に「コピー」ボタンを後付けする。
      // サーバが埋めた履歴と、送信後に差し込む返信の両方をこの関数へ通す。
      function decorateCopyTargets(root) {
        var blocks = root.querySelectorAll('.msg-assistant .bubble pre, .msg-assistant .bubble blockquote');
        Array.prototype.forEach.call(blocks, function (block) {
          if (block.querySelector('.copy-btn')) return;
          // ボタンを入れる前の文字列を控える（ボタンの文言が混ざらないように）
          var text = block.textContent.replace(/\\s+$/, '');
          if (!text) return;
          var button = document.createElement('button');
          button.type = 'button';
          button.className = 'copy-btn';
          button.textContent = 'コピー';
          button.addEventListener('click', function () {
            copyText(text).then(function () {
              button.textContent = 'コピーしました';
              button.classList.add('done');
              setTimeout(function () {
                button.textContent = 'コピー';
                button.classList.remove('done');
              }, 1400);
            }).catch(function () {
              button.textContent = 'コピーできません';
              setTimeout(function () { button.textContent = 'コピー'; }, 1400);
            });
          });
          block.appendChild(button);
        });
      }

      // clipboard API は https / localhost でしか使えないので、駄目なら選択+execCommand に落とす
      function copyText(text) {
        if (navigator.clipboard && navigator.clipboard.writeText) {
          return navigator.clipboard.writeText(text);
        }
        return new Promise(function (resolve, reject) {
          var previous = document.activeElement;
          var area = document.createElement('textarea');
          area.value = text;
          area.setAttribute('readonly', '');
          area.style.position = 'fixed';
          area.style.opacity = '0';
          document.body.appendChild(area);
          area.select();
          var ok = false;
          try { ok = document.execCommand('copy'); } catch (err) { ok = false; }
          document.body.removeChild(area);
          // 書きかけの場所へフォーカスを返す（一時的な textarea に奪われたままにしない）
          if (previous && previous.focus) previous.focus();
          ok ? resolve() : reject(new Error('copy failed'));
        });
      }

      decorateCopyTargets(log);

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
          decorateCopyTargets(pending);
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
