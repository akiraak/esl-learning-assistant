import { test } from "node:test";
import assert from "node:assert/strict";
import { availableFormatSpecs } from "../src/quizQuestions";
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
