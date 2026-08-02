import { test } from "node:test";
import assert from "node:assert/strict";
import {
  canReviewComposition,
  compositionParagraphsHtml,
  compositionPreview,
  compositionStatus,
  draftMatchesLastRound,
  renderCompositionEditorPageHtml,
  renderCompositionReadPageHtml,
  type CompositionChatMessageView,
  type CompositionStatusSource,
  type EditorMisspelling,
} from "../src/compositionView";

// compositionView（docs/plans/writing-web-interface.md）は db.ts を読み込まない純粋モジュールなので、
// 状態判定・段落化・読書用ページの HTML をここで直接検証できる（printView.test.ts と同じ形）。

function source(overrides: Partial<CompositionStatusSource> = {}): CompositionStatusSource {
  return {
    englishText: "I went to school.",
    japaneseText: "学校へ行った。",
    roundCount: 1,
    lastRoundEnglishText: "I went to school.",
    lastRoundJapaneseText: "学校へ行った。",
    ...overrides,
  };
}

test("compositionParagraphsHtml: 空行で段落を分け、段落内の改行は<br>で残す", () => {
  assert.equal(
    compositionParagraphsHtml("First line.\nSecond line.\n\nNext paragraph."),
    "<p>First line.<br>Second line.</p>\n<p>Next paragraph.</p>"
  );
});

test("compositionParagraphsHtml: HTML特殊文字をエスケープする", () => {
  assert.equal(
    compositionParagraphsHtml(`He said "a < b & b > c."`),
    "<p>He said &quot;a &lt; b &amp; b &gt; c.&quot;</p>"
  );
});

test("compositionParagraphsHtml: 空文字・空白のみは空文字を返す", () => {
  assert.equal(compositionParagraphsHtml(""), "");
  assert.equal(compositionParagraphsHtml("  \n \n "), "");
});

test("compositionStatus: ラウンドが無ければ未添削", () => {
  const row = source({ roundCount: 0, lastRoundEnglishText: null, lastRoundJapaneseText: null });
  assert.equal(compositionStatus(row), "draft");
  assert.equal(draftMatchesLastRound(row), false);
});

test("compositionStatus: 下書きが最終ラウンドと同一なら添削済み", () => {
  assert.equal(compositionStatus(source()), "reviewed");
});

test("compositionStatus: 前後の空白差は同一とみなす（iOS の判定と揃える）", () => {
  assert.equal(compositionStatus(source({ englishText: "  I went to school.  " })), "reviewed");
});

test("compositionStatus: 下書きを直したら編集中", () => {
  assert.equal(compositionStatus(source({ englishText: "I went to school today." })), "edited");
  assert.equal(compositionStatus(source({ japaneseText: "今日学校へ行った。" })), "edited");
});

test("canReviewComposition: 英日とも非空で、最終ラウンドから変化しているときだけ送れる", () => {
  assert.equal(canReviewComposition(source()), false);
  assert.equal(canReviewComposition(source({ englishText: "I went to school today." })), true);
  assert.equal(canReviewComposition(source({ englishText: "   " })), false);
  assert.equal(canReviewComposition(source({ englishText: "New text.", japaneseText: "  " })), false);
});

test("canReviewComposition: 初回は下書きが揃っていれば送れる", () => {
  const row = source({ roundCount: 0, lastRoundEnglishText: null, lastRoundJapaneseText: null });
  assert.equal(canReviewComposition(row), true);
});

test("compositionPreview: 英文優先・空なら意図、超過分は…で切る", () => {
  assert.equal(compositionPreview({ englishText: "Hello  there.\nBye.", japaneseText: "やあ。" }), "Hello there. Bye.");
  assert.equal(compositionPreview({ englishText: "   ", japaneseText: "やあ。" }), "やあ。");
  assert.equal(compositionPreview({ englishText: "", japaneseText: "" }), "");
  assert.equal(compositionPreview({ englishText: "abcdefghij", japaneseText: "" }, 5), "abcde…");
});

function editorPage(
  text: string,
  messages: CompositionChatMessageView[] = [],
  misspellings: EditorMisspelling[] = []
) {
  return renderCompositionEditorPageHtml({
    id: 7,
    text,
    misspellings,
    spellcheckUrl: "/admin/writing/7/spellcheck",
    spellSuggestUrl: "/admin/writing/spell-suggest",
    spellIgnoreUrl: "/admin/writing/spell-ignore",
    saveUrl: "/admin/writing/7/save",
    deleteUrl: "/admin/writing/7/delete",
    chatUrl: "/admin/writing/7/chat",
    backHref: "/admin/writing",
    messages,
    chatModel: "claude-sonnet-5",
  });
}

test("執筆ページ: 本文を textarea に入れ、保存・削除・戻りの導線を張る", () => {
  const html = editorPage("Last weekend I visited my grandmother.");

  assert.match(html, /<title>作文 #7<\/title>/);
  assert.match(html, /<textarea id="body"[\s\S]*?>Last weekend I visited my grandmother\.<\/textarea>/);
  assert.match(html, /"\/admin\/writing\/7\/save"/);
  assert.match(html, /action="\/admin\/writing\/7\/delete"/);
  assert.match(html, /href="\/admin\/writing"/);
});

test("執筆ページ: 綴りの下敷きを紙の背後に敷き、標準のスペルチェックは止める", () => {
  const html = editorPage("I recieve a letter.", [], [{ start: 2, end: 9, word: "recieve" }]);

  assert.match(html, /<div class="paper-backdrop" id="backdrop" aria-hidden="true"><\/div>/);
  assert.match(html, /<textarea id="body" class="paper" spellcheck="false"/);
  assert.match(html, /\.paper-backdrop mark \{[\s\S]*?text-decoration: underline wavy;/);
  // 折り返し位置がずれないよう、字組みは textarea と下敷きへ同時に当てる
  assert.match(html, /\.paper, \.paper-backdrop \{[\s\S]*?white-space: pre-wrap;/);
  assert.match(html, /"\/admin\/writing\/7\/spellcheck"/);
  assert.match(html, /var spans = \[\{"start":2,"end":9,"word":"recieve"\}\];/);
});

test("執筆ページ: 初期の綴り誤りを埋め込んでも <script> を閉じさせない", () => {
  const html = editorPage("x", [], [{ start: 0, end: 1, word: "</script><img src=x>" }]);

  assert.doesNotMatch(html, /<\/script><img src=x>/);
  assert.match(html, /\\u003c\/script\\u003cimg src=x>|\\u003c\/script>\\u003cimg src=x>/);
});

test("執筆ページ: 修正候補のポップオーバーと送信先を置く", () => {
  const html = editorPage("I recieve it.", [], [{ start: 2, end: 9, word: "recieve" }]);

  assert.match(html, /<div class="spell-pop" id="spell-pop"><\/div>/);
  assert.match(html, /"\/admin\/writing\/spell-suggest"/);
  assert.match(html, /"\/admin\/writing\/spell-ignore"/);
  assert.match(html, /辞書に追加/);
});

test("執筆ページ: 綴り誤りが無ければ空配列を埋め込む", () => {
  assert.match(editorPage("I received a letter."), /var spans = \[\];/);
});

test("執筆ページ: 左の紙と右のチャット欄・送信先・モデル名を置く", () => {
  const html = editorPage("text");

  assert.match(html, /<div class="paper-pane">/);
  assert.match(html, /<aside class="chat-pane">/);
  assert.match(html, /"\/admin\/writing\/7\/chat"/);
  assert.match(html, /claude-sonnet-5/);
  // 会話が無いときは質問例を出す
  assert.match(html, /<p class="chat-empty">/);
});

test("執筆ページ: 既存のチャットを古い順に描画する（assistant は Markdown、user は素のテキスト）", () => {
  const html = editorPage("text", [
    { role: "user", content: "この文は自然ですか？" },
    { role: "assistant", content: "- ほぼ自然です\n- `met` の方が良いです" },
  ]);

  assert.doesNotMatch(html, /<p class="chat-empty">/);
  assert.match(html, /<div class="msg msg-user"><div class="bubble"><p class="plain">この文は自然ですか？<\/p>/);
  assert.match(html, /<li>ほぼ自然です<\/li>/);
  assert.ok(html.indexOf("msg-user") < html.indexOf("msg-assistant"));
});

test("執筆ページ: チャット本文の HTML を無害化する", () => {
  const html = editorPage("text", [
    { role: "user", content: "<img src=x onerror=alert(1)>" },
    { role: "assistant", content: "<script>alert(2)</script>" },
  ]);

  assert.doesNotMatch(html, /<img src=x/);
  assert.doesNotMatch(html, /<script>alert\(2\)<\/script>/);
  assert.match(html, /&lt;img src=x/);
});

test("執筆ページ: 添削（Review）の UI は置かない", () => {
  const html = editorPage("text");

  assert.doesNotMatch(html, /Review/);
  assert.doesNotMatch(html, /japaneseText/);
  assert.doesNotMatch(html, /Round \d/);
});

test("執筆ページ: 本文の HTML 特殊文字をエスケープする", () => {
  const html = editorPage('</textarea><script>alert(1)</script> a < b & "c"');

  assert.doesNotMatch(html, /<script>alert\(1\)<\/script>/);
  assert.match(html, /&lt;\/textarea&gt;/);
  assert.match(html, /a &lt; b &amp; &quot;c&quot;/);
});

test("執筆ページ: 罫線の間隔と本文の行送りが一致する（ズレると字が罫線から浮く）", () => {
  const html = editorPage("text");

  const lineHeight = html.match(/line-height: (\d+)px/)?.[1];
  assert.ok(lineHeight, "line-height が px 指定であること");
  // 罫線は「(行送り - 1)px から 行送り px まで」を繰り返して引く
  assert.match(
    html,
    new RegExp(`transparent ${Number(lineHeight) - 1}px, [^;]*? ${Number(lineHeight) - 1}px,[\\s\\S]*? ${lineHeight}px`)
  );
  // 自動リサイズも同じ行送りの倍数に丸める
  assert.match(html, new RegExp(`input\\.scrollHeight / ${lineHeight}`));
});

function readPage(rounds: Parameters<typeof renderCompositionReadPageHtml>[0]["rounds"]) {
  return renderCompositionReadPageHtml({
    id: 7,
    title: "My composition",
    meta: "#7 ・ 更新 2026-08-01 ・ 添削 1 回",
    draft: { englishText: "I go to school.", japaneseText: "学校へ行く。" },
    rounds,
    backHref: "/admin/writing/7",
  });
}

test("読書用ページ: 最終ラウンドの添削後英文を本文に置き、ラウンドを古い順に並べる", () => {
  const html = readPage([
    {
      roundIndex: 1,
      englishText: "I go to school yesterday.",
      japaneseText: "昨日学校へ行った。",
      correctedText: "I went to school yesterday.",
      explanation: "- go を went に直しました。",
      createdAt: "2026-08-01 10:00:00 PDT",
    },
    {
      roundIndex: 2,
      englishText: "I went to school yesterday and meet my friend.",
      japaneseText: "昨日学校へ行って友達に会った。",
      correctedText: "I went to school yesterday and met my friend.",
      explanation: "- meet を met に直しました。",
      createdAt: "2026-08-01 11:00:00 PDT",
    },
  ]);

  assert.match(html, /<title>My composition<\/title>/);
  assert.match(html, /#7 ・ 更新 2026-08-01 ・ 添削 1 回/);
  // 本文（final）は最終ラウンドの添削後英文
  assert.match(
    html,
    /<section class="final">\s*<p>I went to school yesterday and met my friend\.<\/p>/
  );
  assert.match(html, /Round 1[\s\S]*Round 2/);
  assert.ok(html.indexOf("Round 1") < html.indexOf("Round 2"));
  // 解説は Markdown としてレンダリングする
  assert.match(html, /<li>go を went に直しました。<\/li>/);
  assert.match(html, /href="\/admin\/writing\/7"/);
});

test("読書用ページ: 未添削なら下書きを本文に出し、その旨を添える", () => {
  const html = readPage([]);

  assert.match(html, /<section class="final">\s*<p>I go to school\.<\/p>/);
  assert.match(html, /この作文はまだ添削されていません。/);
});

test("読書用ページ: 本文の HTML 特殊文字をエスケープする", () => {
  const html = readPage([
    {
      roundIndex: 1,
      englishText: "<script>alert(1)</script>",
      japaneseText: "意図",
      correctedText: "a < b & c",
      explanation: "- `<b>` は書きません",
      createdAt: "2026-08-01 10:00:00 PDT",
    },
  ]);

  assert.doesNotMatch(html, /<script>alert\(1\)<\/script>/);
  assert.match(html, /a &lt; b &amp; c/);
});
