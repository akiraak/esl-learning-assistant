import { test } from "node:test";
import assert from "node:assert/strict";
import { transcriptParagraphsHtml } from "../src/transcriptPrint";

// transcriptPrint（docs/plans/admin-transcription-print-view.md）を対象にする。
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
