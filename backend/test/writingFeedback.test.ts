import { test } from "node:test";
import assert from "node:assert/strict";
import {
  sanitizeWritingHistory,
  validateWritingFeedbackRequest,
  WRITING_HISTORY_MAX_ROUNDS,
  WRITING_TEXT_MAX_LENGTH,
} from "../src/writingFeedback";

// `/api/writing-feedback`（iOS など外部クライアント）と `/admin/writing/:id/review`（Web 画面）が
// 共有する入力バリデーション。import は ocrTranslate → config を読むだけで通信しない。

function round(overrides: Record<string, unknown> = {}) {
  return {
    englishText: "I go to school.",
    japaneseText: "学校へ行く。",
    correctedText: "I go to school.",
    explanation: "- 問題ありません。",
    ...overrides,
  };
}

test("validate: 英文・意図を trim し、解説言語は既定 ja になる", () => {
  const result = validateWritingFeedbackRequest({
    englishText: "  I go to school.  ",
    japaneseText: "  学校へ行く。 ",
  });

  assert.equal(result.ok, true);
  if (!result.ok) return;
  assert.equal(result.value.englishText, "I go to school.");
  assert.equal(result.value.japaneseText, "学校へ行く。");
  assert.equal(result.value.explanationLanguage, "ja");
  assert.deepEqual(result.value.history, []);
});

test("validate: 空白のみの解説言語は既定にフォールバックする", () => {
  const result = validateWritingFeedbackRequest({
    englishText: "Hello.",
    japaneseText: "こんにちは。",
    explanationLanguage: "   ",
  });

  assert.equal(result.ok, true);
  if (!result.ok) return;
  assert.equal(result.value.explanationLanguage, "ja");
});

test("validate: 英文・意図の未入力と型違いを弾く", () => {
  const cases: Array<[unknown, string]> = [
    [{ japaneseText: "こんにちは。" }, "englishText is required"],
    [{ englishText: "   ", japaneseText: "こんにちは。" }, "englishText is required"],
    [{ englishText: "Hello.", japaneseText: "" }, "japaneseText is required"],
    [{ englishText: "Hello.", japaneseText: "こんにちは。", explanationLanguage: 1 }, "explanationLanguage must be a string"],
    [undefined, "englishText is required"],
  ];

  for (const [body, error] of cases) {
    const result = validateWritingFeedbackRequest(body);
    assert.equal(result.ok, false);
    if (result.ok) return;
    assert.equal(result.error, error);
  }
});

test("validate: 上限文字数を超える本文を弾く", () => {
  const long = "a".repeat(WRITING_TEXT_MAX_LENGTH + 1);

  const english = validateWritingFeedbackRequest({ englishText: long, japaneseText: "こんにちは。" });
  assert.equal(english.ok, false);
  if (!english.ok) assert.match(english.error, /^englishText must be/);

  const japanese = validateWritingFeedbackRequest({ englishText: "Hello.", japaneseText: long });
  assert.equal(japanese.ok, false);
  if (!japanese.ok) assert.match(japanese.error, /^japaneseText must be/);
});

test("sanitizeWritingHistory: 配列でない値は空配列になる", () => {
  assert.deepEqual(sanitizeWritingHistory(undefined), []);
  assert.deepEqual(sanitizeWritingHistory("nope"), []);
  assert.deepEqual(sanitizeWritingHistory({ englishText: "x" }), []);
});

test("sanitizeWritingHistory: 英文か添削が空のラウンドは落とす", () => {
  const history = sanitizeWritingHistory([
    round(),
    round({ englishText: "  " }),
    round({ correctedText: "" }),
    "not an object",
    null,
  ]);

  assert.equal(history.length, 1);
  assert.equal(history[0].englishText, "I go to school.");
});

test("sanitizeWritingHistory: 文字列以外のフィールドは空文字に落とす", () => {
  const history = sanitizeWritingHistory([round({ japaneseText: 42, explanation: null })]);

  assert.equal(history.length, 1);
  assert.equal(history[0].japaneseText, "");
  assert.equal(history[0].explanation, "");
});

test("sanitizeWritingHistory: 直近 WRITING_HISTORY_MAX_ROUNDS 件に丸める", () => {
  const raw = Array.from({ length: WRITING_HISTORY_MAX_ROUNDS + 5 }, (_, index) =>
    round({ englishText: `Round ${index}.` })
  );

  const history = sanitizeWritingHistory(raw);

  assert.equal(history.length, WRITING_HISTORY_MAX_ROUNDS);
  assert.equal(history[0].englishText, "Round 5.");
  assert.equal(history.at(-1)!.englishText, `Round ${WRITING_HISTORY_MAX_ROUNDS + 4}.`);
});

test("sanitizeWritingHistory: 長すぎるフィールドは上限文字数で切る", () => {
  const history = sanitizeWritingHistory([
    round({ correctedText: "b".repeat(WRITING_TEXT_MAX_LENGTH + 100) }),
  ]);

  assert.equal(history[0].correctedText.length, WRITING_TEXT_MAX_LENGTH);
});
