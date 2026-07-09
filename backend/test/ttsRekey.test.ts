import { test } from "node:test";
import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

// config は読み込み時に data ディレクトリのパスを確定させ、db はさらに読み込み時に
// sqlite を開いてしまう。実データ（backend/data）を汚さないよう、先に DATA_DIR を
// 一時ディレクトリへ向けてから require する（import 文は先頭に巻き上げられるため使えない）。
process.env.DATA_DIR = fs.mkdtempSync(path.join(os.tmpdir(), "tts-rekey-test-"));

const { config } = require("../src/config") as typeof import("../src/config");
const { getTtsAudioByHash, upsertTtsAudio } = require("../src/db") as typeof import("../src/db");
const { rekeyTtsAudio } = require("../src/ttsStore") as typeof import("../src/ttsStore");

const sha256 = (model: string, text: string) =>
  crypto.createHash("sha256").update(`${model}|${text}`).digest("hex");

const wavPath = (textHash: string) => path.join(config.ttsDir, `${textHash}.wav`);

/// tts_audio に1行（と対応するWAVファイル）を作る。戻り値は text_hash
function seed(text: string, model: "flash" | "pro", options: { withFile?: boolean } = {}): string {
  const textHash = sha256(model, text);
  if (options.withFile ?? true) {
    fs.writeFileSync(wavPath(textHash), Buffer.from(`wav:${text}`));
  }
  upsertTtsAudio({
    text,
    voice: "chobi",
    model,
    textHash,
    filename: `${textHash}.wav`,
    byteSize: 8,
    inputTokens: 1,
    outputTokens: 1,
    costUsd: 0.001,
  });
  return textHash;
}

test("rekeyTtsAudio: 旧キーの行とWAVを新キーへ付け替える（rekeyed）", () => {
  const oldText = "The Sun and the WindThe north wind argued.";
  const newText = "The Sun and the Wind\n\nThe north wind argued.";
  const oldHash = seed(oldText, "flash");

  assert.equal(rekeyTtsAudio(oldHash, newText, "flash"), "rekeyed");

  const newHash = sha256("flash", newText);
  assert.equal(getTtsAudioByHash(oldHash), undefined);
  const row = getTtsAudioByHash(newHash);
  assert.ok(row);
  assert.equal(row.text, newText);
  assert.equal(row.filename, `${newHash}.wav`);
  // WAVの実体はリネームのみ（再合成なし）で内容が保たれる
  assert.equal(fs.existsSync(wavPath(oldHash)), false);
  assert.equal(fs.readFileSync(wavPath(newHash)).toString(), `wav:${oldText}`);
});

test("rekeyTtsAudio: 新旧キーが同じなら何もしない（unchanged）", () => {
  const text = "Single paragraph stays the same.";
  const hash = seed(text, "flash");

  assert.equal(rekeyTtsAudio(hash, text, "flash"), "unchanged");
  assert.ok(getTtsAudioByHash(hash));
  assert.equal(fs.existsSync(wavPath(hash)), true);
});

test("rekeyTtsAudio: 旧キーの行が無ければ何もしない（not_found、冪等）", () => {
  const unknownHash = sha256("flash", "never synthesized text");
  assert.equal(rekeyTtsAudio(unknownHash, "never synthesized text fixed", "flash"), "not_found");
});

test("rekeyTtsAudio: 新キーの行が既にあれば旧行・旧WAVを破棄する（duplicate_removed）", () => {
  const oldText = "HeadingBody duplicated case.";
  const newText = "Heading\n\nBody duplicated case.";
  const oldHash = seed(oldText, "pro");
  const newHash = seed(newText, "pro"); // 移行前に新テキストで生成済みの状態

  assert.equal(rekeyTtsAudio(oldHash, newText, "pro"), "duplicate_removed");

  assert.equal(getTtsAudioByHash(oldHash), undefined);
  assert.equal(fs.existsSync(wavPath(oldHash)), false);
  // 新しい方はそのまま残る
  const row = getTtsAudioByHash(newHash);
  assert.ok(row);
  assert.equal(fs.readFileSync(wavPath(newHash)).toString(), `wav:${newText}`);
});

test("rekeyTtsAudio: WAV欠損時はメタデータのみ付け替える（次回再生時に自己修復させる）", () => {
  const oldText = "Missing fileMissing body.";
  const newText = "Missing file\n\nMissing body.";
  const oldHash = seed(oldText, "flash", { withFile: false });

  assert.equal(rekeyTtsAudio(oldHash, newText, "flash"), "rekeyed");

  const newHash = sha256("flash", newText);
  const row = getTtsAudioByHash(newHash);
  assert.ok(row);
  assert.equal(row.text, newText);
  assert.equal(fs.existsSync(wavPath(newHash)), false);
});

test("rekeyTtsAudio: モデルが違えば別キーなので付け替え対象にならない", () => {
  const oldText = "Model scoped textbody.";
  const newText = "Model scoped text\n\nbody.";
  const oldHashFlash = seed(oldText, "flash");

  // pro として問い合わせると flash の行にはヒットしない
  assert.equal(rekeyTtsAudio(sha256("pro", oldText), newText, "pro"), "not_found");
  assert.ok(getTtsAudioByHash(oldHashFlash));
});
