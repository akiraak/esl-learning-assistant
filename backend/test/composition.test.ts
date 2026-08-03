import { test } from "node:test";
import assert from "node:assert/strict";
import {
  PAGE_NAME_MAX_LENGTH,
  countWords,
  pageDisplayName,
  sanitizePageName,
} from "../src/composition";

test("sanitizePageName: 改行を空白に潰し、前後の空白を落とす", () => {
  assert.equal(sanitizePageName("  下書き  "), "下書き");
  assert.equal(sanitizePageName("下書き\nその2"), "下書き その2");
  assert.equal(sanitizePageName("下書き   その2"), "下書き その2");
});

test("sanitizePageName: 空欄は空文字のまま許す（表示は「ページ N」に落ちる）", () => {
  assert.equal(sanitizePageName(""), "");
  assert.equal(sanitizePageName("   \n  "), "");
});

test("sanitizePageName: 上限文字数で切る", () => {
  const long = "あ".repeat(PAGE_NAME_MAX_LENGTH + 10);
  assert.equal(sanitizePageName(long).length, PAGE_NAME_MAX_LENGTH);
});

test("pageDisplayName: 名前が空なら並び順から「ページ N」を作る", () => {
  assert.equal(pageDisplayName("清書", 2), "清書");
  assert.equal(pageDisplayName("", 1), "ページ 1");
  assert.equal(pageDisplayName("   ", 3), "ページ 3");
});

// docs/plans/writing-word-count.md: 執筆画面の右上に出す語数。画面側の JS も
// WORD_PATTERN_SOURCE をそのまま使うので、規則の検証はここに集約する。
test("countWords: 空白で区切られた語を数える", () => {
  assert.equal(countWords("Last weekend I visited my grandmother."), 6);
  assert.equal(countWords("  He   left.\n\nShe stayed.  "), 4);
});

test("countWords: 空文字・記号だけは 0", () => {
  assert.equal(countWords(""), 0);
  assert.equal(countWords("   \n  "), 0);
  assert.equal(countWords("... --- !?"), 0);
});

test("countWords: 語中のアポストロフィ・ハイフンは繋いだまま1語", () => {
  assert.equal(countWords("I don't know."), 3);
  assert.equal(countWords("It is a well-known story."), 5);
  assert.equal(countWords("don’t"), 1);
  // 語の外にぶら下がる記号は語に含めない（数は変わらない）
  assert.equal(countWords("'quoted' word"), 2);
});

test("countWords: 数字と日本語も1語として数える", () => {
  assert.equal(countWords("I have 2 cats."), 4);
  assert.equal(countWords("祖母を訪ねた"), 1);
});
