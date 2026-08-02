import { test } from "node:test";
import assert from "node:assert/strict";
import {
  buildTitlePrompt,
  COMPOSITION_TITLE_MAX_LENGTH,
  sanitizeCompositionTitle,
} from "../src/compositionTitle";

// docs/plans/composition-title.md: 生成結果も手入力も同じ整形を通してから保存する。
// 「適度な短さ」はプロンプトの語数指示 + ここでの上限で担保する。

test("sanitizeCompositionTitle: 改行・連続空白を1行にまとめ、前後を落とす", () => {
  assert.equal(sanitizeCompositionTitle("  A Visit\nto  My   Grandmother \n"), "A Visit to My Grandmother");
});

test("sanitizeCompositionTitle: 対になった囲みの引用符だけを剥がす", () => {
  assert.equal(sanitizeCompositionTitle('"A Visit to My Grandmother"'), "A Visit to My Grandmother");
  assert.equal(sanitizeCompositionTitle("「祖母を訪ねた日」"), "祖母を訪ねた日");
  // 文中の引用符は残す（囲みではない）
  assert.equal(sanitizeCompositionTitle('The Word "Home"'), 'The Word "Home"');
});

test("sanitizeCompositionTitle: 末尾のピリオド・句点を落とす", () => {
  assert.equal(sanitizeCompositionTitle("A Visit to My Grandmother."), "A Visit to My Grandmother");
  assert.equal(sanitizeCompositionTitle("祖母を訪ねた日。"), "祖母を訪ねた日");
});

test("sanitizeCompositionTitle: 上限で切る", () => {
  const long = "a".repeat(COMPOSITION_TITLE_MAX_LENGTH + 30);
  assert.equal(sanitizeCompositionTitle(long).length, COMPOSITION_TITLE_MAX_LENGTH);
});

test("sanitizeCompositionTitle: 空白のみは空文字（＝タイトル無しとして扱う）", () => {
  assert.equal(sanitizeCompositionTitle("   \n "), "");
});

test("buildTitlePrompt: 本文と短さの条件をプロンプトへ入れる", () => {
  const prompt = buildTitlePrompt("  Last weekend I visited my grandmother.  ");

  assert.match(prompt, /Last weekend I visited my grandmother\./);
  assert.match(prompt, /5〜8語程度/);
  assert.match(prompt, /末尾にピリオドを付けない/);
});
