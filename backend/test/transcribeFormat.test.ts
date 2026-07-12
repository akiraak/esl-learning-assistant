import { test } from "node:test";
import assert from "node:assert/strict";
import { formatTranscriptParagraphs } from "../src/transcribe";

// formatTranscriptParagraphs（docs/plans/audio-transcript-readability.md）を対象にする。
// transcribe の import は config を読むだけで通信しない。

test("空行区切りの出力はそのまま維持する", () => {
  const input = "First paragraph here. Two sentences.\n\nSecond paragraph here.";
  assert.equal(formatTranscriptParagraphs(input), input);
});

test("単一改行のみの出力は空行区切りに変換する", () => {
  assert.equal(
    formatTranscriptParagraphs("First paragraph here.\nSecond paragraph here."),
    "First paragraph here.\n\nSecond paragraph here."
  );
});

test("CRLF・3連以上の改行・前後空白を正規化する", () => {
  assert.equal(
    formatTranscriptParagraphs("  First one. \r\n\r\n\r\nSecond one. \n Third one.\n"),
    "First one.\n\nSecond one.\n\nThird one."
  );
});

test("改行ゼロの長文は約3文ごとに段落化する", () => {
  const sentences = [
    "One is here.",
    "Two is here.",
    "Three is here!",
    "Four is here?",
    "Five is here.",
    "Six is here.",
    "Seven is here.",
  ];
  assert.equal(
    formatTranscriptParagraphs(sentences.join(" ")),
    [sentences.slice(0, 3).join(" "), sentences.slice(3, 6).join(" "), sentences[6]].join("\n\n")
  );
});

test("短い出力は1段落のまま", () => {
  const input = "Hello there. How are you doing today? I am fine.";
  assert.equal(formatTranscriptParagraphs(input), input);
});

test("敬称略語（Mr. 等）は文境界と見なさない", () => {
  const sentences = [
    "I met Mr. Smith today.",
    "He was with Dr. Brown.",
    "They talked a lot.",
    "Then they left.",
    "It was late.",
    "We went home.",
  ];
  assert.equal(
    formatTranscriptParagraphs(sentences.join(" ")),
    [sentences.slice(0, 3).join(" "), sentences.slice(3, 6).join(" ")].join("\n\n")
  );
});

test("閉じ引用符つきの文末も境界として扱う", () => {
  const sentences = [
    'He said, "Stop right now."',
    "Then he walked away.",
    "Nobody followed him.",
    "The room went quiet.",
    "She stood up.",
    "Everyone watched her.",
  ];
  assert.equal(
    formatTranscriptParagraphs(sentences.join(" ")),
    [sentences.slice(0, 3).join(" "), sentences.slice(3, 6).join(" ")].join("\n\n")
  );
});
