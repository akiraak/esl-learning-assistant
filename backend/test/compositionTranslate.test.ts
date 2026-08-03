import { test } from "node:test";
import assert from "node:assert/strict";
import {
  WRITING_TRANSLATE_CONTEXT_CHARS,
  WRITING_TRANSLATE_MAX_LENGTH,
  buildTranslatePrompt,
  clampContext,
  normalizeSelection,
  selectionContext,
  selectionHash,
} from "../src/compositionTranslate";

// docs/plans/writing-selection-translate.md: 選択は短くて文脈依存が強いので、
// 前後 200 文字を添えて「選択部分だけ訳す」よう頼む。キャッシュキーにも文脈を含める。

test("normalizeSelection: 前後の空白だけ落とし、中の改行はそのまま残す", () => {
  assert.equal(normalizeSelection("  He left.\nShe stayed.  "), "He left.\nShe stayed.");
  assert.equal(normalizeSelection("   "), "");
});

test("selectionContext: 前後それぞれ 200 文字まで切り出す", () => {
  const before = "b".repeat(300);
  const after = "a".repeat(300);
  const body = before + "SELECTED" + after;
  const context = selectionContext(body, before.length, before.length + "SELECTED".length);

  assert.equal(context.before.length, WRITING_TRANSLATE_CONTEXT_CHARS);
  assert.equal(context.after.length, WRITING_TRANSLATE_CONTEXT_CHARS);
  // before は選択に近い側（末尾）、after は選択に近い側（先頭）を残す
  assert.equal(context.before, before.slice(-WRITING_TRANSLATE_CONTEXT_CHARS));
  assert.equal(context.after, after.slice(0, WRITING_TRANSLATE_CONTEXT_CHARS));
});

test("selectionContext: 足りないときはある分だけ、本文の端なら空文字", () => {
  const body = "He left. She stayed.";

  const middle = selectionContext(body, 9, 20);
  assert.equal(middle.before, "He left. ");
  assert.equal(middle.after, "");

  const head = selectionContext(body, 0, 8);
  assert.equal(head.before, "");
  assert.equal(head.after, " She stayed.");

  // 本文全体を選んだら文脈は両方とも空（文脈なしの頼み方に切り替わる）
  const whole = selectionContext(body, 0, body.length);
  assert.equal(whole.before, "");
  assert.equal(whole.after, "");
});

test("selectionContext: 範囲が本文からはみ出しても壊れない", () => {
  const body = "He left.";
  const context = selectionContext(body, -5, 999);
  assert.equal(context.before, "");
  assert.equal(context.after, "");
});

test("clampContext: クライアントが多く送ってきても上限まで切り詰める", () => {
  const before = "b".repeat(500);
  const after = "a".repeat(500);
  const clamped = clampContext(before, after);

  assert.equal(clamped.before, before.slice(-WRITING_TRANSLATE_CONTEXT_CHARS));
  assert.equal(clamped.after, after.slice(0, WRITING_TRANSLATE_CONTEXT_CHARS));
});

test("selectionHash: 同じ (テキスト・言語・文脈) で同値", () => {
  assert.equal(
    selectionHash("He left.", "ja", "Yesterday. ", " She stayed."),
    selectionHash("He left.", "ja", "Yesterday. ", " She stayed.")
  );
});

test("selectionHash: 言語・文脈が違えば別値（文脈が変われば訳も変わり得る）", () => {
  const base = selectionHash("He left.", "ja", "Yesterday. ", " She stayed.");

  assert.notEqual(base, selectionHash("He left.", "en", "Yesterday. ", " She stayed."));
  assert.notEqual(base, selectionHash("He left.", "ja", "Today. ", " She stayed."));
  assert.notEqual(base, selectionHash("He left.", "ja", "Yesterday. ", " She went."));
  assert.notEqual(base, selectionHash("She left.", "ja", "Yesterday. ", " She stayed."));
});

test("selectionHash: 区切りをまたいだ組み替えで衝突しない", () => {
  assert.notEqual(
    selectionHash("He left.", "ja", "A", "B"),
    selectionHash("He left.", "ja", "A B", "")
  );
});

test("buildTranslatePrompt: 文脈があれば <selection> で訳す範囲を囲む", () => {
  const prompt = buildTranslatePrompt("He left.", "ja", "Yesterday. ", " She stayed.");

  assert.match(prompt, /<selection>He left\.<\/selection>/);
  assert.match(prompt, /Yesterday\. <selection>/);
  assert.match(prompt, /<\/selection> She stayed\./);
  assert.match(prompt, /"ja"/);
  // 文脈は訳文に含めないことを明示する
  assert.match(prompt, /訳文には含めないでください/);
});

test("buildTranslatePrompt: 文脈が両方とも空なら文脈なしの頼み方にする", () => {
  const prompt = buildTranslatePrompt("He left.", "ja", "", "");

  assert.doesNotMatch(prompt, /<selection>/);
  assert.match(prompt, /He left\./);
  assert.match(prompt, /"ja"/);
});

test("WRITING_TRANSLATE_MAX_LENGTH: 画面とサーバで共有する上限は 1000 文字", () => {
  assert.equal(WRITING_TRANSLATE_MAX_LENGTH, 1000);
  assert.equal("a".repeat(WRITING_TRANSLATE_MAX_LENGTH).length <= WRITING_TRANSLATE_MAX_LENGTH, true);
  assert.equal("a".repeat(WRITING_TRANSLATE_MAX_LENGTH + 1).length > WRITING_TRANSLATE_MAX_LENGTH, true);
});
