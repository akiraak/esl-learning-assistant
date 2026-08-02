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
});

test("insertComposition: 1枚目のページが一緒に作られる（作文は常に1枚以上を持つ）", () => {
  const pages = db.listCompositionPages(db.insertComposition("ja"));

  assert.equal(pages.length, 1);
  assert.equal(pages[0].position, 1);
  assert.equal(pages[0].name, "");
  assert.equal(pages[0].english_text, "");
});

test("updateCompositionJapaneseText: 意図だけを上書きし、本文のミラーには触らない", () => {
  const id = db.insertComposition("ja");
  db.updateCompositionPageText(db.listCompositionPages(id)[0].id, "I go to school.");

  assert.equal(db.updateCompositionJapaneseText(id, "学校へ行く。"), true);

  const row = db.getComposition(id)!;
  assert.equal(row.japanese_text, "学校へ行く。");
  assert.equal(row.english_text, "I go to school.");
  assert.equal(db.updateCompositionJapaneseText(999999, "x"), false);
});

test("insertComposition: タイトルは空文字で始まる（空欄なら一覧は本文の先頭を出す）", () => {
  assert.equal(db.getComposition(db.insertComposition("ja"))!.title, "");
});

test("updateCompositionTitle: タイトルだけを更新し、本文には触らない", () => {
  const id = db.insertComposition("ja");
  db.updateCompositionPageText(db.listCompositionPages(id)[0].id, "I went to school.");
  db.updateCompositionJapaneseText(id, "学校へ行った。");

  assert.equal(db.updateCompositionTitle(id, "A Day at School"), true);

  const row = db.getComposition(id)!;
  assert.equal(row.title, "A Day at School");
  assert.equal(row.english_text, "I went to school.");
  assert.equal(row.japanese_text, "学校へ行った。");
});

test("updateCompositionTitle: 存在しない ID は false", () => {
  assert.equal(db.updateCompositionTitle(999999, "title"), false);
});

test("listCompositions: 更新日時の新しい順に並ぶ", () => {
  const older = db.insertComposition("ja");
  db.updateCompositionPageText(db.listCompositionPages(older)[0].id, "Older draft.");
  const newer = db.insertComposition("ja");
  db.updateCompositionPageText(db.listCompositionPages(newer)[0].id, "Newer draft.");

  const rows = db.listCompositions(100);
  const newerRow = rows.find((row) => row.id === newer)!;
  const olderRow = rows.find((row) => row.id === older)!;

  assert.ok(rows.indexOf(newerRow) < rows.indexOf(olderRow));
  assert.equal(newerRow.english_text, "Newer draft.");
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

test("deleteComposition: 子のチャットも一緒に消える", () => {
  const id = db.insertComposition("ja");
  db.insertCompositionChatMessage({ compositionId: id, role: "user", content: "消える質問" });

  db.deleteComposition(id);

  assert.equal(db.getComposition(id), undefined);
  assert.equal(db.listCompositionChatMessages(id).length, 0);
});

// --- ページ（composition_pages）----------------------------------------------

test("insertCompositionPage: 末尾に足され、position が 1 から順に振られる", () => {
  const id = db.insertComposition("ja");
  const second = db.insertCompositionPage(id, "清書");
  const third = db.insertCompositionPage(id);

  assert.equal(second.position, 2);
  assert.equal(second.name, "清書");
  assert.equal(third.position, 3);
  assert.equal(third.name, "");
  assert.deepEqual(
    db.listCompositionPages(id).map((page) => page.position),
    [1, 2, 3]
  );
});

test("getCompositionPage: 別の作文のページ ID では取れない", () => {
  const first = db.insertComposition("ja");
  const second = db.insertComposition("ja");
  const page = db.listCompositionPages(first)[0];

  assert.ok(db.getCompositionPage(first, page.id));
  assert.equal(db.getCompositionPage(second, page.id), undefined);
});

test("updateCompositionPageText: そのページだけを書き換え、他のページには触らない", () => {
  const id = db.insertComposition("ja");
  const first = db.listCompositionPages(id)[0];
  const second = db.insertCompositionPage(id);

  assert.equal(db.updateCompositionPageText(second.id, "Second page."), true);

  const pages = db.listCompositionPages(id);
  assert.equal(pages[0].english_text, "");
  assert.equal(pages[1].english_text, "Second page.");
  assert.equal(db.getCompositionPage(id, first.id)!.english_text, "");
});

test("updateCompositionPageText: 先頭ページは compositions.english_text にもミラーする（一覧のプレビュー用）", () => {
  const id = db.insertComposition("ja");
  const first = db.listCompositionPages(id)[0];
  const second = db.insertCompositionPage(id);

  db.updateCompositionPageText(first.id, "First page.");
  assert.equal(db.getComposition(id)!.english_text, "First page.");

  // 2枚目以降はミラーしない（一覧に出るのは先頭ページのまま）
  db.updateCompositionPageText(second.id, "Second page.");
  assert.equal(db.getComposition(id)!.english_text, "First page.");
});

test("updateCompositionPageText: 存在しないページは false", () => {
  assert.equal(db.updateCompositionPageText(999999, "x"), false);
});

test("renameCompositionPage: タブ名だけを変える", () => {
  const id = db.insertComposition("ja");
  const page = db.listCompositionPages(id)[0];
  db.updateCompositionPageText(page.id, "Body.");

  assert.equal(db.renameCompositionPage(page.id, "下書き"), true);

  const after = db.getCompositionPage(id, page.id)!;
  assert.equal(after.name, "下書き");
  assert.equal(after.english_text, "Body.");
  assert.equal(db.renameCompositionPage(999999, "x"), false);
});

test("deleteCompositionPage: 消した後ろの position を詰める", () => {
  const id = db.insertComposition("ja");
  const first = db.listCompositionPages(id)[0];
  const second = db.insertCompositionPage(id, "2枚目");
  const third = db.insertCompositionPage(id, "3枚目");

  assert.equal(db.deleteCompositionPage(id, second.id), "deleted");

  const pages = db.listCompositionPages(id);
  assert.deepEqual(
    pages.map((page) => [page.id, page.position]),
    [
      [first.id, 1],
      [third.id, 2],
    ]
  );
});

test("deleteCompositionPage: 最後の1枚は消せない", () => {
  const id = db.insertComposition("ja");
  const page = db.listCompositionPages(id)[0];

  assert.equal(db.deleteCompositionPage(id, page.id), "last-page");
  assert.equal(db.listCompositionPages(id).length, 1);
});

test("deleteCompositionPage: 無いページ・他の作文のページは not-found", () => {
  const id = db.insertComposition("ja");
  db.insertCompositionPage(id);
  const other = db.insertComposition("ja");
  const otherPage = db.listCompositionPages(other)[0];

  assert.equal(db.deleteCompositionPage(id, 999999), "not-found");
  assert.equal(db.deleteCompositionPage(id, otherPage.id), "not-found");
});

test("reorderCompositionPages: 渡された順に position を振り直す", () => {
  const id = db.insertComposition("ja");
  const first = db.listCompositionPages(id)[0];
  const second = db.insertCompositionPage(id, "2枚目");
  const third = db.insertCompositionPage(id, "3枚目");

  assert.equal(db.reorderCompositionPages(id, [third.id, first.id, second.id]), "reordered");

  assert.deepEqual(
    db.listCompositionPages(id).map((page) => [page.id, page.position]),
    [
      [third.id, 1],
      [first.id, 2],
      [second.id, 3],
    ]
  );
});

test("reorderCompositionPages: 過不足・重複・他の作文のページが混ざれば何もしない", () => {
  const id = db.insertComposition("ja");
  const first = db.listCompositionPages(id)[0];
  const second = db.insertCompositionPage(id);
  const other = db.listCompositionPages(db.insertComposition("ja"))[0];
  const before = db.listCompositionPages(id).map((page) => [page.id, page.position]);

  assert.equal(db.reorderCompositionPages(id, [first.id]), "mismatch");
  assert.equal(db.reorderCompositionPages(id, [first.id, first.id]), "mismatch");
  assert.equal(db.reorderCompositionPages(id, [first.id, other.id]), "mismatch");
  assert.equal(db.reorderCompositionPages(id, [first.id, second.id, other.id]), "mismatch");

  assert.deepEqual(db.listCompositionPages(id).map((page) => [page.id, page.position]), before);
});

test("migrateCompositionsToPages: ページが0件の作文に1枚作って本文を移す", () => {
  const id = db.insertComposition("ja");
  // ページ導入前の状態を作る（本文は compositions 側にあり、ページは 1 枚も無い）。
  // db.ts はこの形を作る API を持たないので、同じ SQLite ファイルを別接続で開いて直接書く。
  const raw = new (require("better-sqlite3"))(path.join(dataDir, "db.sqlite"));
  raw.prepare("UPDATE compositions SET english_text = ? WHERE id = ?").run("Legacy body.", id);
  raw.prepare("DELETE FROM composition_pages WHERE composition_id = ?").run(id);
  raw.close();
  assert.equal(db.listCompositionPages(id).length, 0);

  assert.equal(db.migrateCompositionsToPages(), 1);

  const pages = db.listCompositionPages(id);
  assert.equal(pages.length, 1);
  assert.equal(pages[0].position, 1);
  assert.equal(pages[0].name, "");
  assert.equal(pages[0].english_text, "Legacy body.");
  // 2度目は何もしない（既にページを持つ作文は対象外）
  assert.equal(db.migrateCompositionsToPages(), 0);
});

test("deleteComposition: 子のページも一緒に消える", () => {
  const id = db.insertComposition("ja");
  db.insertCompositionPage(id, "2枚目");

  db.deleteComposition(id);

  assert.equal(db.listCompositionPages(id).length, 0);
});
