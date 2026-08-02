import { test } from "node:test";
import assert from "node:assert/strict";
import {
  compositionListTitle,
  compositionParagraphsHtml,
  compositionPreview,
  renderCompositionEditorPageHtml,
  type CompositionChatMessageView,
  type EditorMisspelling,
} from "../src/compositionView";

// compositionView（docs/plans/writing-web-interface.md）は db.ts を読み込まない純粋モジュールなので、
// 見出しの整形と執筆画面の HTML をここで直接検証できる（printView.test.ts と同じ形）。

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

test("compositionPreview: 英文優先・空なら意図、超過分は…で切る", () => {
  assert.equal(compositionPreview({ englishText: "Hello  there.\nBye.", japaneseText: "やあ。" }), "Hello there. Bye.");
  assert.equal(compositionPreview({ englishText: "   ", japaneseText: "やあ。" }), "やあ。");
  assert.equal(compositionPreview({ englishText: "", japaneseText: "" }), "");
  assert.equal(compositionPreview({ englishText: "abcdefghij", japaneseText: "" }, 5), "abcde…");
});

test("compositionListTitle: タイトルがあればタイトル、空欄なら本文の先頭", () => {
  const draft = { englishText: "Last weekend I visited my grandmother.", japaneseText: "先週末は祖母を訪ねた。" };

  assert.equal(compositionListTitle({ ...draft, title: "A Visit to My Grandmother" }), "A Visit to My Grandmother");
  assert.equal(compositionListTitle({ ...draft, title: "   " }), "Last weekend I visited my grandmother.");
  // 本文もタイトルも空なら意図、どちらも無ければ空文字（呼び出し側が「(空の作文)」に落とす）
  assert.equal(compositionListTitle({ englishText: "", japaneseText: "先週末の話。", title: "" }), "先週末の話。");
  assert.equal(compositionListTitle({ englishText: "", japaneseText: "", title: "" }), "");
});

test("compositionListTitle: 長いタイトルは…で切り、改行は1行にまとめる", () => {
  assert.equal(compositionListTitle({ englishText: "", japaneseText: "", title: "abcdefghij" }, 5), "abcde…");
  assert.equal(compositionListTitle({ englishText: "", japaneseText: "", title: "A  Visit\nHome" }), "A Visit Home");
});

function editorPage(
  text: string,
  messages: CompositionChatMessageView[] = [],
  misspellings: EditorMisspelling[] = [],
  title = ""
) {
  return renderCompositionEditorPageHtml({
    id: 7,
    title,
    titleMaxLength: 120,
    titleUrl: "/admin/writing/7/title",
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

test("執筆ページ: 紙の上部にタイトル入力欄と本文からの生成ボタンを置く", () => {
  const html = editorPage("Last weekend I visited my grandmother.", [], [], 'A Visit to "Grandma"');

  assert.match(html, /<input id="title" class="title-input" type="text" maxlength="120"/);
  assert.match(html, /value="A Visit to &quot;Grandma&quot;"/);
  assert.match(html, /<button type="button" class="title-gen" id="title-generate">本文から生成<\/button>/);
  assert.match(html, /"\/admin\/writing\/7\/title"/);
  // タイトルは本文と同じ自動保存に相乗りする
  assert.match(html, /JSON\.stringify\(\{ englishText: input\.value, title: titleInput\.value \}\)/);
  // タイトルは罫線紙の中ではなく、紙の外（上）に独立した見出しとして置く
  assert.match(html, /<div class="title-row">[\s\S]*?<\/div>\s*<div class="sheet">/);
  assert.doesNotMatch(html, /<div class="sheet">[\s\S]*?class="title-input"/);
  // 左右の位置は紙の本文と揃え（紙と同じ --pad-x）、紙と同じ地色のもう一枚の紙として浮かせる
  assert.match(html, /\.title-row \{[\s\S]*?padding: 14px var\(--pad-x\);/);
  assert.match(html, /\.title-row \{[\s\S]*?background-color: #FFFDF7;[\s\S]*?box-shadow:/);
});

test("執筆ページ: タイトルが空欄なら空の入力欄と案内のプレースホルダを出す", () => {
  const html = editorPage("Last weekend I visited my grandmother.");

  assert.match(html, /placeholder="タイトル（空欄なら一覧に本文の先頭が出ます）"/);
  assert.match(html, /value=""/);
});

test("執筆ページ: 紙を横いっぱいに広げ、AI 欄との境界を掴んで動かせるようにする", () => {
  const html = editorPage("Last weekend I visited my grandmother.");

  // 紙はペイン幅いっぱい（中央寄せの max-width を持たない）。左右には少しだけ余白を残す
  assert.doesNotMatch(html, /\.sheet \{[\s\S]*?max-width: 44em;/);
  assert.match(html, /\.sheet \{[\s\S]*?margin: 0 24px 64px;/);
  // 仕切りには掴めることが分かるつまみ（左右の矢印）を出す
  assert.match(html, /\.resizer::after \{[\s\S]*?background-image: url\("data:image\/svg\+xml,/);
  assert.match(html, /cursor: col-resize;/);
  // 紙 / 仕切り / AI 欄の 3 列。AI 欄の幅は --chat-w で動かす
  assert.match(html, /grid-template-columns: minmax\(0, 1fr\) 6px var\(--chat-w\);/);
  assert.match(html, /<div class="resizer" id="resizer" role="separator"/);
  assert.match(html, /resizer\.addEventListener\('pointerdown'/);
  // 動かした幅はブラウザに覚えさせる
  assert.match(html, /localStorage\.setItem\(WIDTH_KEY/);
  assert.match(html, /var WIDTH_KEY = 'composition\.chatWidth';/);
});

test("執筆ページ: AI 返信の英文ブロックにコピーボタンを付ける", () => {
  const html = editorPage("Last weekend I visited my grandmother.", [
    { role: "user", content: "この文は自然ですか？" },
    { role: "assistant", content: "時制を直すと自然です。\n\n```\nI visited my grandmother last weekend.\n```" },
  ]);

  // ``` は pre/code として描画され、そこへ後からボタンを足す
  assert.match(html, /<pre><code>I visited my grandmother last weekend\.\n<\/code><\/pre>/);
  assert.match(html, /function decorateCopyTargets\(root\)/);
  assert.match(html, /\.msg-assistant \.bubble pre, \.msg-assistant \.bubble blockquote/);
  assert.match(html, /button\.textContent = 'コピー';/);
  // 新しい返信を差し込んだ直後にも同じ処理を通す
  assert.match(html, /decorateCopyTargets\(pending\);/);
  // clipboard API が使えない環境の逃げ道も持つ
  assert.match(html, /document\.execCommand\('copy'\)/);
  assert.match(html, /\.copy-btn \{/);
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
