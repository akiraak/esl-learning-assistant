import { test } from "node:test";
import assert from "node:assert/strict";
import {
  compositionDocumentTitle,
  compositionListTitle,
  compositionParagraphsHtml,
  compositionPreview,
  renderCompositionEditorPageHtml,
  wordCountLabel,
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

test("compositionDocumentTitle: タイトル → 本文の先頭 → 作文 #id の順に拾う", () => {
  assert.equal(
    compositionDocumentTitle({ id: 7, title: "A Visit  Home\n", text: "Last weekend..." }),
    "A Visit Home"
  );
  assert.equal(
    compositionDocumentTitle({ id: 7, title: "  ", text: "Last weekend I visited\nmy grandmother." }),
    "Last weekend I visited my grandmother."
  );
  assert.equal(compositionDocumentTitle({ id: 7, title: "", text: "  " }), "作文 #7");
});

test("compositionDocumentTitle: 長いときは…で切る", () => {
  assert.equal(compositionDocumentTitle({ id: 7, title: "abcdefghij", text: "" }, 5), "abcde…");
});

test("執筆画面: ブラウザタブの見出しにタイトル（無ければ本文の先頭）を出す", () => {
  assert.match(editorPage("Hello there.", [], [], "My Trip"), /<title>My Trip<\/title>/);
  assert.match(editorPage("Hello there."), /<title>Hello there\.<\/title>/);
  assert.match(editorPage(""), /<title>作文 #7<\/title>/);
  assert.match(editorPage("", [], [], `a & b <c>`), /<title>a &amp; b &lt;c&gt;<\/title>/);
  // タブのアイコン（アプリと同じもの）も張る
  assert.match(editorPage(""), /<link rel="icon" type="image\/png" href="\/admin\/icon\.png">/);
});

function editorPage(
  text: string,
  messages: CompositionChatMessageView[] = [],
  misspellings: EditorMisspelling[] = [],
  title = ""
) {
  return editorPageWith({ pages: [{ id: 11, name: "", position: 1, text, misspellings }], messages, title });
}

/// タブまわりを見るとき用。ページ一覧・選択中のページ・上限を差し替えられる。
function editorPageWith(overrides: Partial<Parameters<typeof renderCompositionEditorPageHtml>[0]>) {
  const pages = overrides.pages ?? [{ id: 11, name: "", position: 1, text: "", misspellings: [] }];
  return renderCompositionEditorPageHtml({
    id: 7,
    title: "",
    titleMaxLength: 120,
    titleUrl: "/admin/writing/7/title",
    pages,
    activePageId: pages[0].id,
    pagesUrl: "/admin/writing/7/pages",
    pageNameMaxLength: 40,
    maxPages: 20,
    spellcheckUrl: "/admin/writing/7/spellcheck",
    spellSuggestUrl: "/admin/writing/spell-suggest",
    spellIgnoreUrl: "/admin/writing/spell-ignore",
    saveUrl: "/admin/writing/7/save",
    deleteUrl: "/admin/writing/7/delete",
    chatUrl: "/admin/writing/7/chat",
    translateUrl: "/admin/writing/7/translate",
    backHref: "/admin/writing",
    iconHref: "/admin/icon.png",    messages: [],
    chatModel: "claude-sonnet-5",
    ...overrides,
  });
}

test("執筆ページ: 本文を textarea に入れ、保存・削除・戻りの導線を張る", () => {
  const html = editorPage("Last weekend I visited my grandmother.");

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
  assert.match(html, /englishText: input\.value, title: titleInput\.value/);
  // タイトルは罫線紙の中ではなく、紙の外（上）に独立した見出しとして置く
  assert.match(html, /<div class="title-row">[\s\S]*?<\/div>\s*<div class="paper-stack">/);
  assert.doesNotMatch(html, /<div class="sheet">[\s\S]*?class="title-input"/);
  // 左右の位置は紙の本文と揃え（紙と同じ --pad-x）、紙と同じ地色のもう一枚の紙として浮かせる
  assert.match(html, /\.title-row \{[^}]*padding: 8px var\(--pad-x\);/);
  assert.match(html, /\.title-row \{[^}]*background-color: #FFFDF7;[^}]*box-shadow:/);
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
  assert.match(html, /\.paper-stack \{[^}]*margin: 0 24px 64px;/);
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
  // 赤線の位置はページごとに持つ（タブを切り替えても混ざらない）
  assert.match(html, /"spans":\[\{"start":2,"end":9,"word":"recieve"\}\]/);
  assert.match(html, /var spans = currentPage\(\)\.spans;/);
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
  assert.match(editorPage("I received a letter."), /"spans":\[\]/);
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

// --- 紙のタブ（docs/plans/composition-pages-tabs.md）--------------------------

function tabbedPage(overrides: Partial<Parameters<typeof renderCompositionEditorPageHtml>[0]> = {}) {
  return editorPageWith({
    pages: [
      { id: 11, name: "下書き", position: 1, text: "First.", misspellings: [] },
      { id: 12, name: "", position: 2, text: "Second.", misspellings: [] },
    ],
    activePageId: 11,
    ...overrides,
  });
}

test("タブ: タイトルカードと紙の間にタブ列を置き、選択中のタブに aria-selected を付ける", () => {
  const html = tabbedPage();

  assert.match(html, /<div class="tabs" id="tabs" role="tablist">/);
  assert.match(html, /<div class="tab is-active" data-page-id="11"[^>]*aria-selected="true"/);
  assert.match(html, /<div class="tab" data-page-id="12"[^>]*aria-selected="false"/);
  // タブ列は紙の上（タイトルカードの下）
  assert.match(html, /<div class="tabs"[\s\S]*?<div class="sheet">/);
  // 選択中のページの本文が紙に載る
  assert.match(html, /<textarea id="body"[\s\S]*?>First\.<\/textarea>/);
});

test("タブ: 名前が空のタブは並び順から「ページ N」を出す", () => {
  const html = tabbedPage();

  assert.match(html, /<span class="tab-name">下書き<\/span>/);
  assert.match(html, /<span class="tab-name">ページ 2<\/span>/);
  // スクリプト側の描き直しも同じ規則
  assert.match(html, /'ページ ' \+ item\.position/);
});

test("タブ: タブ名の HTML 特殊文字をエスケープする", () => {
  const html = editorPageWith({
    pages: [{ id: 11, name: '<img src=x> & "y"', position: 1, text: "", misspellings: [] }],
    activePageId: 11,
  });

  assert.doesNotMatch(html, /<span class="tab-name"><img src=x>/);
  assert.match(html, /&lt;img src=x&gt; &amp; &quot;y&quot;/);
});

test("タブ: 選択中のタブは紙と同じ地色で下辺が無く、影は紙だけが落とす", () => {
  const html = tabbedPage();

  // 選択中＝紙そのもの（同じ地色・紙へつながるよう下辺の線は消す）
  assert.match(html, /\.tab\.is-active \{[^}]*background: #FFFDF7;[^}]*border-bottom-color: transparent;/);
  // 非選択＝一段沈んだ色と境界線で、後ろに重なった別紙に見せる
  assert.match(html, /\.tab \{[^}]*background: #F5EFE1;[^}]*border: 1px solid #DFDACB;/);
  // 影は紙に 1 つだけ。親（タブ列を含む四角）に持たせると、タブが無い右側まで
  // 影の落ちない帯が広がって地色より明るく浮くので持たせない
  assert.match(html, /\.sheet \{[^}]*box-shadow: 0 1px 2px/);
  assert.doesNotMatch(html, /\.paper-stack \{[^}]*box-shadow:/);
  // 紙の影がタブの下辺に掛からないよう、タブ列は紙より前に描く
  assert.match(html, /\.tabs \{[^}]*z-index: 1;/);
  assert.match(html, /\.tabs \{[^}]*margin-bottom: 0;/);
  // タブの字は UI 部品ではなく紙の一部に見せる（本文と同じセリフ体）
  assert.match(html, /\.tab \{[^}]*"Iowan Old Style", Georgia/);
  // 狭いときは折り返さず横スクロール
  assert.match(html, /\.tabs \{[^}]*overflow-x: auto;/);
});

test("タブ: 削除の「×」は選択中のタブにだけ出し、最後の 1 枚では押せない", () => {
  const many = tabbedPage();
  assert.match(many, /<div class="tab is-active" data-page-id="11"[\s\S]*?<button type="button" class="tab-del" data-page-id="11"[^>]*>×<\/button>/);
  assert.doesNotMatch(many, /class="tab-del" data-page-id="12"/);
  assert.doesNotMatch(many, /class="tab-del"[^>]*disabled/);

  const single = editorPage("text");
  assert.match(single, /class="tab-del"[^>]*disabled/);
});

test("タブ: 「＋」はページ数が上限に達したら押せない", () => {
  assert.doesNotMatch(tabbedPage(), /class="tab-add"[^>]*disabled/);
  assert.match(tabbedPage({ maxPages: 2 }), /class="tab-add"[^>]*disabled/);
});

test("タブ: 切り替えは自動保存を確定させてから本文を差し替える", () => {
  const html = tabbedPage();

  assert.match(html, /function switchTo\(id\) \{[\s\S]*?save\(\)\.then\(function \(\) \{\s*showPage\(id\);/);
  // 保存は「いま選択中のページ」宛て
  assert.match(html, /JSON\.stringify\(\{ pageId: activeId, englishText: input\.value/);
  // 本文と赤線はページごとに持つ
  assert.match(html, /var pages = \[\{"id":11/);
  assert.match(html, /"text":"First\.","spans":\[\]/);
});

test("タブ: 選択中のページはブラウザに覚えさせ、次に開いたときに復元する", () => {
  const html = tabbedPage();

  assert.match(html, /var ACTIVE_KEY = 'writing:' \+ 7 \+ ':activePage';/);
  assert.match(html, /localStorage\.setItem\(ACTIVE_KEY/);
  // 消えたページを指していたらサーバの既定（先頭）のままにする
  assert.match(html, /if \(remembered && remembered !== activeId && pageById\(remembered\)\) showPage\(remembered\);/);
});

test("タブ: 追加・リネーム・削除の送信先を持つ", () => {
  const html = tabbedPage();

  assert.match(html, /var pagesUrl = "\/admin\/writing\/7\/pages";/);
  assert.match(html, /pagesUrl \+ '\/' \+ id \+ '\/rename'/);
  assert.match(html, /pagesUrl \+ '\/' \+ id \+ '\/delete'/);
  // ダブルクリック（と F2）でその場が入力欄になる
  assert.match(html, /tabsEl\.addEventListener\('dblclick'/);
  assert.match(html, /if \(event\.key === 'F2'\)/);
  // 本文の入ったページを消すときは確認する
  assert.match(html, /if \(target\.text\.trim\(\) && !confirm\(/);
});

test("タブ: ドラッグで並べ替えられ、落ちる位置に目印を出す", () => {
  const html = tabbedPage();

  assert.match(html, /<div class="tab is-active" data-page-id="11"[^>]*draggable="true"/);
  assert.match(html, /tabsEl\.addEventListener\('dragstart'/);
  assert.match(html, /tabsEl\.addEventListener\('drop'/);
  assert.match(html, /pagesUrl \+ '\/reorder'/);
  assert.match(html, /JSON\.stringify\(\{ pageIds: order \}\)/);
  assert.match(html, /\.tab\.drop-before \{[^}]*box-shadow: inset 2px 0 0/);
  // スクリプト側で描き直したタブも掴める
  assert.match(html, /tab\.draggable = true;/);
});

test("タブ: チャットとタイトル生成には選択中のページを伝える", () => {
  const html = tabbedPage();

  assert.match(html, /JSON\.stringify\(\{ message: text, pageId: activeId, includeAllPages: allPages\.checked \}\)/);
  assert.match(html, /JSON\.stringify\(\{ pageId: activeId \}\)/);
});

test("チャット: 「全ページを含める」の切り替えをヘッダに置き、ブラウザに覚えさせる", () => {
  const html = tabbedPage();

  assert.match(html, /<input type="checkbox" id="chat-all-pages">全ページを含める/);
  // 会話全体にかかる設定なので、送信のたびではなくブラウザ側に残す
  assert.match(html, /composition\.chatAllPages/);
});

test("執筆ページ: 本文の HTML 特殊文字をエスケープする", () => {
  const html = editorPage('</textarea><script>alert(1)</script> a < b & "c"');

  assert.doesNotMatch(html, /<script>alert\(1\)<\/script>/);
  assert.match(html, /&lt;\/textarea&gt;/);
  assert.match(html, /a &lt; b &amp; &quot;c&quot;/);
});

test("執筆ページ: 本文が短いうちは紙が余りを埋め、縦スクロールバーを出さない", () => {
  const html = editorPage("Short.");

  // ツールバー・タイトル・タブの高さを数えた calc（ズレるとバーが出る）は使わない
  assert.doesNotMatch(html, /min-height: calc\(100vh/);
  // ペインは縦の列で、紙のかたまりだけが余りを埋める
  assert.match(html, /\.paper-pane \{[^}]*display: flex; flex-direction: column;/);
  assert.match(html, /\.paper-stack \{[^}]*flex: 1 0 auto;/);
  assert.match(html, /\.sheet \{[^}]*flex: 1 0 auto;/);
  // 入力欄自身は伸ばさない（autogrow が自分の丈を測って伸び続けるため）
  assert.doesNotMatch(html, /\.paper \{[^}]*flex: 1 0 auto;/);
  // 代わりに、本文より下の罫線をクリックしたら入力欄へ送る
  assert.match(html, /document\.querySelector\('\.sheet'\)\.addEventListener\('mousedown'/);
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

// docs/plans/writing-selection-translate.md: 英文を選ぶと、その真下に和訳の紙片を出す。
test("執筆ページ: 選択範囲の翻訳の紙片と POST 先を持つ", () => {
  const html = editorPage("Last weekend I visited my grandmother.");

  assert.match(html, /<div class="trans-pop" id="trans-pop"/);
  assert.match(html, /var translateUrl = "\/admin\/writing\/7\/translate";/);
  // 選択が確定してから投げる（引きずっている最中に何度も叩かない）
  assert.match(html, /input\.addEventListener\('select', onSelectionChanged\)/);
  // 選択が固定されてから1秒後に投げる（docs/plans/archive/writing-translate-delay.md）
  assert.match(html, /var TRANSLATE_DELAY_MS = 1000;/);
  assert.match(html, /transTimer = setTimeout\(runTranslate, TRANSLATE_DELAY_MS\)/);
  // 位置決めは下敷きの選択マークから取る（textarea 自体からは座標が取れない）
  assert.match(html, /backdrop\.querySelector\('mark\[data-sel="1"\]'\)/);
});

test("執筆ページ: 選択が長すぎるときは通信せず注意文を出す", () => {
  const html = editorPage("text");

  assert.match(html, /var TRANSLATE_MAX_LENGTH = 1000;/);
  assert.match(html, /var TRANSLATE_CONTEXT_CHARS = 200;/);
  assert.match(html, /text\.length > TRANSLATE_MAX_LENGTH/);
});

// docs/plans/writing-translate-copy.md: 和訳はチャットの英文ブロックと同じ .copy-btn で持ち出せる。
test("執筆ページ: 和訳のときだけコピーボタンを添える", () => {
  const html = editorPage("Last weekend I visited my grandmother.");

  // 案内文（.note）には付けず、和訳のときだけ付ける
  assert.match(html, /if \(!isNote\) \{[\s\S]*?transCopyButton\(message\)/);
  // 紙片は幅が狭いので、右上に重ねず訳文の下へ1段置く（「コピーしました」で訳文に被らない）
  assert.match(html, /\.trans-pop \.copy-row \{ display: flex; justify-content: flex-end;/);
  assert.match(html, /\.trans-pop \.copy-btn \{ position: static; \}/);
  assert.match(html, /row\.className = 'copy-row';/);
  // チャットの英文ブロックと同じ見た目・同じクリップボード処理を使い回す
  assert.match(html, /button\.className = 'copy-btn';[\s\S]*?copyText\(text\)/);
  // 押しても本文の選択が解けないよう mousedown で拾って既定動作を止める
  assert.match(html, /button\.addEventListener\('mousedown', function \(event\) \{\s*event\.preventDefault\(\);/);
});

// docs/plans/writing-word-count.md: ツールバーの右上に語数を出す。
test("wordCountLabel: 1語のときだけ単数形、選択中は「選択」を前に付ける", () => {
  assert.equal(wordCountLabel(0), "0 words");
  assert.equal(wordCountLabel(1), "1 word");
  assert.equal(wordCountLabel(12), "12 words");
  assert.equal(wordCountLabel(12, true), "選択 12 words");
});

test("執筆ページ: ツールバーに語数を出し、本文と選択に追随させる", () => {
  const html = editorPage("Last weekend I visited my grandmother.");

  // 初期表示はサーバが数えて埋める（開いた直後にちらつかせない）
  assert.match(html, /<span class="status" id="word-count">6 words<\/span>/);
  assert.match(html, /<span class="status" id="save-status">保存済み<\/span>/);
  // 画面側もサーバと同じ規則で数える
  assert.match(html, /var WORD_RE = new RegExp\("\[\\\\p\{L\}/);
  // 選択中はその範囲の語数に切り替える
  assert.match(html, /var text = selected \? input\.value\.slice\(selRange\.start, selRange\.end\) : input\.value;/);
  // 本文か選択が動けば必ず通る renderMarks で数え直す
  assert.match(html, /backdrop\.replaceChildren\(fragment\);\s*\/\/[^\n]*\n\s*updateWordCount\(\);/);
});

test("執筆ページ: ページを切り替えたら前のページの選択を持ち越さない", () => {
  const html = editorPage("Last weekend I visited my grandmother.");

  assert.match(html, /closePopover\(\);\s*\/\/[^\n]*\n\s*clearSelectionMark\(\);\s*\n\s*renderTabs\(\);/);
});
