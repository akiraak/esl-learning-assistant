import { test } from "node:test";
import assert from "node:assert/strict";
import { isContextNormalizationConsistent } from "../src/wordNormalize";
import type { WordNormalization } from "../src/wordNormalize";

// isContextNormalizationConsistent（docs/plans/word-tap-normalize-wrong-word.md Phase 1）を対象にする。
// wordNormalize の import は Anthropic クライアントを構築するだけで通信しない。

function n(status: WordNormalization["status"], lemma: string, reason = ""): WordNormalization {
  return { status, lemma, reason };
}

test("phrase_part: lemma のトークンにタップ語が含まれれば一貫", () => {
  assert.ok(isContextNormalizationConsistent("up", n("phrase_part", "look up", "文中の『up』は句動詞『look up』の一部です")));
  assert.ok(isContextNormalizationConsistent("care", n("phrase_part", "take care of", "『care』は『take care of』の一部です")));
});

test("phrase_part: タップ語が構成語でない lemma（目的語の誤発動）は不一貫", () => {
  // 再現例: 文 "I heard that you need to fill out this form." で "form" をタップ → "fill out"
  assert.ok(!isContextNormalizationConsistent("form", n("phrase_part", "fill out", "『form』は句動詞『fill out』の目的語です")));
});

test("phrase_part: 大文字小文字の違いは無視して照合する", () => {
  assert.ok(isContextNormalizationConsistent("Up", n("phrase_part", "look up", "")));
});

test("inflected/misspelled: reason にタップ語の引用があれば一貫", () => {
  assert.ok(isContextNormalizationConsistent("ran", n("inflected", "run", "『ran』は動詞『run』の過去形です")));
  assert.ok(isContextNormalizationConsistent("Heard", n("inflected", "hear", "「heard」は「hear」の過去形です")));
  assert.ok(isContextNormalizationConsistent("writed", n("misspelled", "write", "『writed』は『write』の綴り間違いです")));
});

test("inflected/misspelled: reason がタップ語に言及しない（別語の正規化）は不一貫", () => {
  // 報告例: "form" のタップに「『heard』は『hear』の過去形です」が返る
  assert.ok(!isContextNormalizationConsistent("form", n("inflected", "hear", "「heard」は「hear」の過去形です")));
});

test("訂正を提案しない status は常に一貫扱い", () => {
  assert.ok(isContextNormalizationConsistent("form", n("canonical", "form")));
  assert.ok(isContextNormalizationConsistent("Tokyo", n("proper_noun", "Tokyo")));
  assert.ok(isContextNormalizationConsistent("look up", n("phrase", "look up")));
  assert.ok(isContextNormalizationConsistent("xyzzy", n("unknown", "xyzzy")));
});
