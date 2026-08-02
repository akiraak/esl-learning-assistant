import { test, after } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { findMisspellings } from "../src/spellcheck";

// db.ts は import 時に config.dbPath の SQLite を開くため、実データ（backend/data）を汚さないよう
// DATA_DIR を一時ディレクトリへ差し替えてから遅延 require する（compositions.test.ts と同じ形）。
const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), "esl-spell-ignore-test-"));
process.env.DATA_DIR = dataDir;
const db = require("../src/db") as typeof import("../src/db");

after(() => {
  fs.rmSync(dataDir, { recursive: true, force: true });
});

test("spell_ignored_words: 小文字化して保存し、重複追加でも増えない", () => {
  assert.deepEqual(db.listSpellIgnoredWords(), []);

  assert.equal(db.insertSpellIgnoredWord("  Kozakai "), "kozakai");
  assert.equal(db.insertSpellIgnoredWord("KOZAKAI"), "kozakai");
  assert.equal(db.insertSpellIgnoredWord("Akira"), "akira");
  assert.equal(db.insertSpellIgnoredWord("   "), null);

  assert.deepEqual(db.listSpellIgnoredWords(), ["akira", "kozakai"]);
});

test("無視リストに入れた語は綴り検査で赤くならない", () => {
  const text = "Akira Kozakai wrote it.";
  assert.deepEqual(
    findMisspellings(text).map((item) => item.word),
    ["Akira", "Kozakai"]
  );

  const ignored = [...db.listSpellIgnoredWords()];
  assert.deepEqual(findMisspellings(text, ignored), []);
});
