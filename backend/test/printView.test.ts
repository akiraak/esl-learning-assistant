import { test } from "node:test";
import assert from "node:assert/strict";
import { renderPrintPageHtml, transcriptParagraphsHtml } from "../src/printView";

// printView（docs/plans/admin-transcription-print-view.md /
// admin-print-views-photo-document-translation.md）を対象にする。
// import は transcribe → config を読むだけで通信しない。

test("空行区切りの英文を段落ごとの<p>にする", () => {
  assert.equal(
    transcriptParagraphsHtml("First paragraph here. Two sentences.\n\nSecond paragraph here."),
    "<p>First paragraph here. Two sentences.</p>\n<p>Second paragraph here.</p>"
  );
});

test("旧形式（単一改行のみ）も段落<p>に再整形する", () => {
  assert.equal(
    transcriptParagraphsHtml("First paragraph here.\nSecond paragraph here."),
    "<p>First paragraph here.</p>\n<p>Second paragraph here.</p>"
  );
});

test("HTML特殊文字をエスケープする", () => {
  assert.equal(
    transcriptParagraphsHtml(`He said "a < b & b > c."`),
    "<p>He said &quot;a &lt; b &amp; b &gt; c.&quot;</p>"
  );
});

test("空文字・空白のみは空文字を返す", () => {
  assert.equal(transcriptParagraphsHtml(""), "");
  assert.equal(transcriptParagraphsHtml("  \n \n"), "");
});

test("renderPrintPageHtml: lang・タイトル・meta・本文・戻りリンクを埋め込む", () => {
  const html = renderPrintPageHtml({
    lang: "ja",
    title: "My Podcast",
    meta: "#4 ・ 2026-07-12 ・ 訳 (ja)",
    bodyHtml: "<p>本文です。</p>",
    backHref: "/admin/transcriptions",
  });
  assert.match(html, /<html lang="ja">/);
  assert.match(html, /<title>My Podcast<\/title>/);
  assert.match(html, /<h1>My Podcast<\/h1>/);
  assert.match(html, /#4 ・ 2026-07-12 ・ 訳 \(ja\)/);
  assert.match(html, /<p>本文です。<\/p>/);
  assert.match(html, /<a href="\/admin\/transcriptions">← 一覧に戻る<\/a>/);
  // 印刷時にツールバーを消すスタイルが入っていること
  assert.match(html, /@media print[\s\S]*\.toolbar \{ display: none; \}/);
  // 印刷時のみのページ番号（@page マージンボックス）が入っていること
  assert.match(html, /@bottom-center[\s\S]*counter\(page\) " \/ " counter\(pages\)/);
});

test("renderPrintPageHtml: タイトル・meta はエスケープし、本文HTMLはそのまま通す", () => {
  const html = renderPrintPageHtml({
    lang: "en",
    title: `A <b> & "quote"`,
    meta: "<script>",
    bodyHtml: "<h2>Heading</h2>",
    backHref: "/admin",
    backLabel: "← 詳細に戻る",
  });
  assert.match(html, /<h1>A &lt;b&gt; &amp; &quot;quote&quot;<\/h1>/);
  assert.match(html, /&lt;script&gt;/);
  assert.doesNotMatch(html, /<script>/);
  assert.match(html, /<h2>Heading<\/h2>/);
  assert.match(html, /← 詳細に戻る/);
});
