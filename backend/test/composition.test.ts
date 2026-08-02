import { test } from "node:test";
import assert from "node:assert/strict";
import { PAGE_NAME_MAX_LENGTH, pageDisplayName, sanitizePageName } from "../src/composition";

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
