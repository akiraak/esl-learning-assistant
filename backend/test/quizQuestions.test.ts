import { test } from "node:test";
import assert from "node:assert/strict";
import { availableFormatSpecs, validateAndConvert } from "../src/quizQuestions";
import type { WordInfo } from "../src/wordInfo";

// availableFormatSpecs のフレーズゲート（docs/plans/word-phrase-support.md §4）を対象にする。
// quizQuestions の import は Anthropic クライアントを構築するだけで通信しない。

/// 全形式の素材ゲート（isAvailable）が通るフル素材の WordInfo
function fullMaterialInfo(): WordInfo {
  return {
    senses: [
      {
        meaning: "調べる",
        englishDefinition: "to search for information in a book or database",
        partOfSpeech: "句動詞",
        note: null,
      },
    ],
    pronunciation: { ipa: "/lʊk ʌp/", syllables: null },
    inflections: [
      { form: "past tense", text: "looked up" },
      { form: "third-person singular", text: "looks up" },
    ],
    examples: [{ english: "I looked it up in the dictionary.", translation: "辞書で調べた。" }],
    collocations: ["look up a word"],
    synonyms: ["search for"],
    antonyms: ["ignore"],
    usageNote: null,
    cefrLevel: "B1",
    etymology: null,
    register: null,
    commonMistakes: null,
  };
}

test("availableFormatSpecs: 1語の単語は vc2 を含む全形式が対象になる", () => {
  const ids = availableFormatSpecs("run", fullMaterialInfo()).map((spec) => spec.id);
  assert.ok(ids.includes("vc2"));
  assert.deepEqual(
    ids.sort(),
    ["tc2", "tc3", "tc4", "tc5", "tc6", "tc7", "tt1", "vc1", "vc2", "vc3", "vc4", "vt1", "vtt1"]
  );
});

test("availableFormatSpecs: フレーズは vc2（綴り4択）のみ除外される", () => {
  const singleIds = availableFormatSpecs("run", fullMaterialInfo()).map((spec) => spec.id);
  const phraseIds = availableFormatSpecs("look up", fullMaterialInfo()).map((spec) => spec.id);
  assert.ok(!phraseIds.includes("vc2"));
  assert.deepEqual(
    phraseIds.sort(),
    singleIds.filter((id) => id !== "vc2").sort()
  );
});

test("availableFormatSpecs: フレーズでも素材ゲートは従来どおり効く", () => {
  const info = fullMaterialInfo();
  info.inflections = []; // tc7 の素材なし（by heart のような固定イディオム）
  info.synonyms = []; // tc4 の素材なし
  const ids = availableFormatSpecs("by heart", info).map((spec) => spec.id);
  assert.ok(!ids.includes("tc7"));
  assert.ok(!ids.includes("tc4"));
  assert.ok(!ids.includes("vc2"));
  assert.ok(ids.includes("vt1")); // ディクテーションはフレーズでも成立
});

test("availableFormatSpecs: 前後の空白だけではフレーズ扱いにしない", () => {
  const ids = availableFormatSpecs(" run ", fullMaterialInfo()).map((spec) => spec.id);
  assert.ok(ids.includes("vc2"));
});

// validateAndConvert の audioText 混入対策
// （docs/plans/quiz-audiotext-strip-non-audio-formats.md）。
// AI が音声不要形式にも audioText（displayText のコピー等）を返すことがあり、
// 素通しすると TTS プリ合成の無駄コストと iOS 側の不要な音声ボタン表示になる。

function specById(id: string) {
  const spec = availableFormatSpecs("run", fullMaterialInfo()).find((s) => s.id === id);
  assert.ok(spec, `spec ${id} not found`);
  return spec;
}

test("validateAndConvert: 音声不要形式（choices）は AI が返した audioText を捨てる", () => {
  const question = validateAndConvert(
    {
      format: "tc3",
      variantIndex: 0,
      instruction: "Choose the word that fits the blank.",
      displayText: "She _____ every morning.",
      audioText: "She runs every morning.",
      answerType: "choices",
      options: ["runs", "eats", "reads", "sings"],
      correctIndex: 0,
      acceptedAnswers: null,
    },
    "run",
    specById("tc3")
  );
  assert.ok(question);
  assert.equal(question.audioText, null);
  assert.equal(question.displayText, "She _____ every morning.");
});

test("validateAndConvert: 音声不要形式（typing）は AI が返した audioText を捨てる", () => {
  const question = validateAndConvert(
    {
      format: "tt1",
      variantIndex: 0,
      instruction: "Type the word that matches this definition.",
      displayText: "to move fast on foot",
      audioText: "to move fast on foot",
      answerType: "typing",
      options: null,
      correctIndex: null,
      acceptedAnswers: ["run"],
    },
    "run",
    specById("tt1")
  );
  assert.ok(question);
  assert.equal(question.audioText, null);
});

test("validateAndConvert: 音声形式の audioText は保持される", () => {
  const question = validateAndConvert(
    {
      format: "vc1",
      variantIndex: 0,
      instruction: "Listen. Which is the correct definition of the word you hear?",
      displayText: null,
      audioText: " run ",
      answerType: "choices",
      options: ["to move fast on foot", "to sleep", "to eat", "to sing"],
      correctIndex: 0,
      acceptedAnswers: null,
    },
    "run",
    specById("vc1")
  );
  assert.ok(question);
  assert.equal(question.audioText, "run");
});

test("validateAndConvert: 音声形式で audioText が無ければ棄却される", () => {
  const question = validateAndConvert(
    {
      format: "vc1",
      variantIndex: 0,
      instruction: "Listen. Which is the correct definition of the word you hear?",
      displayText: null,
      audioText: null,
      answerType: "choices",
      options: ["to move fast on foot", "to sleep", "to eat", "to sing"],
      correctIndex: 0,
      acceptedAnswers: null,
    },
    "run",
    specById("vc1")
  );
  assert.equal(question, null);
});

// 活用形ラベルの互換（2026-07-04 の英語化 bad7982 の前後両対応）。
// 日本語のみ対応だったため、英語ラベルの新データで tc7 が黙って生成されなくなっていた。
test("tc7 の素材ゲート: 日本語・英語どちらの活用形ラベルでも成立する", () => {
  const japanese = fullMaterialInfo();
  japanese.inflections = [{ form: "過去形", text: "ran" }];
  assert.ok(availableFormatSpecs("run", japanese).some((spec) => spec.id === "tc7"));

  const english = fullMaterialInfo();
  english.inflections = [{ form: "past tense", text: "ran" }];
  assert.ok(availableFormatSpecs("run", english).some((spec) => spec.id === "tc7"));

  const unknown = fullMaterialInfo();
  unknown.inflections = [{ form: "???", text: "ran" }];
  assert.ok(!availableFormatSpecs("run", unknown).some((spec) => spec.id === "tc7"));
});
