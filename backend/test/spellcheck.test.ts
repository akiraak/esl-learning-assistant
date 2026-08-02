import { test } from "node:test";
import assert from "node:assert/strict";
import { findMisspellings, suggestCorrections } from "../src/spellcheck";

// spellcheck（docs/plans/writing-spellcheck-highlight.md）は db.ts を読み込まない純粋モジュールなので、
// トークナイズ規則・オフセット・例外辞書をここで直接検証できる（compositionView.test.ts と同じ形）。

function words(text: string, ignored: string[] = []): string[] {
  return findMisspellings(text, ignored).map((item) => item.word);
}

test("findMisspellings: 誤字を拾い、オフセットが本文と一致する", () => {
  const text = "I recieve a letter yesteday.";
  const found = findMisspellings(text);

  assert.deepEqual(
    found.map((item) => item.word),
    ["recieve", "yesteday"]
  );
  for (const item of found) {
    assert.equal(text.slice(item.start, item.end), item.word);
  }
});

test("suggestCorrections: 誤りの語に候補を返し、正しい語には返さない", () => {
  const suggestions = suggestCorrections("yesteday");
  assert.ok(suggestions.includes("yesterday"));
  assert.ok(suggestions.length <= 3);

  assert.deepEqual(suggestCorrections("yesterday"), []);
  assert.deepEqual(suggestCorrections(""), []);
  assert.deepEqual(suggestCorrections("2026"), []);
  // 2 回目はキャッシュから返る（同じ内容であること）
  assert.deepEqual(suggestCorrections("yesteday"), suggestions);
});

test("findMisspellings: 正しい英文では何も返さない", () => {
  assert.deepEqual(words("I received a letter yesterday."), []);
});

test("findMisspellings: 空文字・空白のみは空配列", () => {
  assert.deepEqual(findMisspellings(""), []);
  assert.deepEqual(findMisspellings("   \n\t "), []);
});

test("findMisspellings: 短縮形はアポストロフィごと1語として扱う", () => {
  // 分割すると doesn / ve が誤検出になる（辞書は doesn't を持っている）
  assert.deepEqual(words("It doesn't matter and I've done it."), []);
  // タイポグラフィのアポストロフィも同じ扱い
  assert.deepEqual(words("It doesn’t matter."), []);
});

test("findMisspellings: 引用符に囲まれた語を誤検出しない", () => {
  assert.deepEqual(words("He said 'hello' to me."), []);
});

test("findMisspellings: ハイフン付き複合語は片ごとに判定する", () => {
  // 辞書は well-known を持たないので、分けずに判定すると正しい綴りが誤りになる
  assert.deepEqual(words("It is a well-known story."), []);

  const text = "It is a well-knwon story.";
  const found = findMisspellings(text);
  assert.deepEqual(
    found.map((item) => item.word),
    ["knwon"]
  );
  assert.equal(text.slice(found[0].start, found[0].end), "knwon");
});

test("findMisspellings: 数字・略語・URL・メール・日本語はスキップする", () => {
  assert.deepEqual(words("In 2026 the 30th U.S. team won."), []);
  assert.deepEqual(words("See https://example.com/recieve or mail foo@bar.com."), []);
  assert.deepEqual(words("これは日本語の文です。—記号も。"), []);
});

test("findMisspellings: 例外語は大小・前後空白の違いを無視して除外する", () => {
  assert.deepEqual(words("Akira wrote it."), ["Akira"]);
  assert.deepEqual(words("Akira wrote it.", ["  akira  "]), []);
  assert.deepEqual(words("akira wrote it.", ["Akira"]), []);
});

test("findMisspellings: 大文字化された正しい語は誤検出しない", () => {
  assert.deepEqual(words("I RECEIVE it."), []);
  assert.deepEqual(words("I RECIEVE it.").length, 1);
});

test("findMisspellings: 複数行でもオフセットが本文と一致する", () => {
  const text = "First line has a mistke.\n\nSecond line is fine.\nThird has anothr one.";
  const found = findMisspellings(text);
  assert.deepEqual(
    found.map((item) => item.word),
    ["mistke", "anothr"]
  );
  for (const item of found) {
    assert.equal(text.slice(item.start, item.end), item.word);
  }
});
