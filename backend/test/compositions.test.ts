import { test, after } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

// db.ts は import 時に config.dbPath の SQLite を開くため、実データ（backend/data）を汚さないよう
// DATA_DIR を一時ディレクトリへ差し替えてから遅延 require する
// （静的 import は巻き上げられて代入より先に実行されてしまう）。
const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), "esl-compositions-test-"));
process.env.DATA_DIR = dataDir;
const db = require("../src/db") as typeof import("../src/db");

after(() => {
  fs.rmSync(dataDir, { recursive: true, force: true });
});

test("insertComposition: 空の下書きが作られ、作成/更新日時が入る", () => {
  const id = db.insertComposition("ja");
  const row = db.getComposition(id);

  assert.ok(row);
  assert.equal(row.english_text, "");
  assert.equal(row.japanese_text, "");
  assert.equal(row.explanation_language, "ja");
  assert.equal(row.created_at, row.updated_at);
  assert.equal(db.listCompositionRounds(id).length, 0);
});

test("updateCompositionDraft: 本文を上書きし updated_at を進める", () => {
  const id = db.insertComposition("ja");
  const before = db.getComposition(id)!;

  assert.equal(db.updateCompositionDraft(id, "I go to school.", "学校へ行く。"), true);

  const after = db.getComposition(id)!;
  assert.equal(after.english_text, "I go to school.");
  assert.equal(after.japanese_text, "学校へ行く。");
  assert.ok(after.updated_at >= before.updated_at);
});

test("updateCompositionDraft: 存在しない ID は false（削除済みへの保存要求）", () => {
  assert.equal(db.updateCompositionDraft(999999, "x", "y"), false);
});

test("insertCompositionRound: round_index が 1 から採番され、古い順に取り出せる", () => {
  const id = db.insertComposition("ja");

  const first = db.insertCompositionRound({
    compositionId: id,
    englishText: "I go to school yesterday.",
    japaneseText: "昨日学校へ行った。",
    correctedText: "I went to school yesterday.",
    explanation: "- go を過去形 went に直しました。",
    model: "claude-test",
  });
  const second = db.insertCompositionRound({
    compositionId: id,
    englishText: "I went to school yesterday and meet my friend.",
    japaneseText: "昨日学校へ行って友達に会った。",
    correctedText: "I went to school yesterday and met my friend.",
    explanation: "- meet を met に直しました。",
    model: "claude-test",
  });

  assert.equal(first, 1);
  assert.equal(second, 2);

  const rounds = db.listCompositionRounds(id);
  assert.deepEqual(
    rounds.map((round) => round.round_index),
    [1, 2]
  );
  assert.equal(rounds[0].corrected_text, "I went to school yesterday.");
  assert.equal(rounds[1].model, "claude-test");
});

test("insertCompositionRound: 親の updated_at も進む（一覧の並び替えに使う）", () => {
  const id = db.insertComposition("ja");
  const before = db.getComposition(id)!;

  db.insertCompositionRound({
    compositionId: id,
    englishText: "Hello.",
    japaneseText: "こんにちは。",
    correctedText: "Hello.",
    explanation: "- 問題ありません。",
    model: "claude-test",
  });

  assert.ok(db.getComposition(id)!.updated_at >= before.updated_at);
});

test("listCompositions: ラウンド数と最終ラウンドの本文を含み、更新日時の新しい順に並ぶ", () => {
  const older = db.insertComposition("ja");
  db.updateCompositionDraft(older, "Older draft.", "古い方。");
  const newer = db.insertComposition("ja");
  db.updateCompositionDraft(newer, "Newer draft.", "新しい方。");
  db.insertCompositionRound({
    compositionId: newer,
    englishText: "Newer draft.",
    japaneseText: "新しい方。",
    correctedText: "A newer draft.",
    explanation: "- 冠詞を足しました。",
    model: "claude-test",
  });

  const rows = db.listCompositions(100);
  const newerRow = rows.find((row) => row.id === newer)!;
  const olderRow = rows.find((row) => row.id === older)!;

  assert.ok(rows.indexOf(newerRow) < rows.indexOf(olderRow));
  assert.equal(newerRow.round_count, 1);
  assert.equal(newerRow.last_round_english_text, "Newer draft.");
  assert.equal(newerRow.last_round_japanese_text, "新しい方。");
  assert.equal(olderRow.round_count, 0);
  assert.equal(olderRow.last_round_english_text, null);
});

test("listCompositions: limit / offset でページングできる", () => {
  const first = db.listCompositions(1, 0);
  const second = db.listCompositions(1, 1);

  assert.equal(first.length, 1);
  assert.equal(second.length, 1);
  assert.notEqual(first[0].id, second[0].id);
});

test("チャット: 発言を古い順に積み、assistant 行にコストを記録する", () => {
  const id = db.insertComposition("ja");

  db.insertCompositionChatMessage({ compositionId: id, role: "user", content: "この文は自然ですか？" });
  const reply = db.insertCompositionChatMessage({
    compositionId: id,
    role: "assistant",
    content: "- ほぼ自然です",
    model: "claude-sonnet-5",
    inputTokens: 120,
    outputTokens: 45,
    costUsd: 0.0012,
  });

  const messages = db.listCompositionChatMessages(id);
  assert.deepEqual(
    messages.map((message) => message.role),
    ["user", "assistant"]
  );
  assert.equal(messages[0].content, "この文は自然ですか？");
  assert.equal(messages[0].model, null);
  assert.equal(messages[0].cost_usd, 0);
  assert.equal(reply.model, "claude-sonnet-5");
  assert.equal(reply.input_tokens, 120);
  assert.equal(reply.cost_usd, 0.0012);
});

test("チャット: 作文ごとに独立したスレッドになる", () => {
  const first = db.insertComposition("ja");
  const second = db.insertComposition("ja");
  db.insertCompositionChatMessage({ compositionId: first, role: "user", content: "1つめの質問" });

  assert.equal(db.listCompositionChatMessages(first).length, 1);
  assert.equal(db.listCompositionChatMessages(second).length, 0);
});

test("deleteComposition: 子のラウンドとチャットも一緒に消える", () => {
  const id = db.insertComposition("ja");
  db.insertCompositionRound({
    compositionId: id,
    englishText: "Delete me.",
    japaneseText: "消される。",
    correctedText: "Delete me.",
    explanation: "-",
    model: "claude-test",
  });
  db.insertCompositionChatMessage({ compositionId: id, role: "user", content: "消える質問" });

  db.deleteComposition(id);

  assert.equal(db.getComposition(id), undefined);
  assert.equal(db.listCompositionRounds(id).length, 0);
  assert.equal(db.listCompositionChatMessages(id).length, 0);
});
