import { test } from "node:test";
import assert from "node:assert/strict";
import { createJobStore } from "../src/jobStore";

// 文書抽出ジョブ（documentJobs.ts）の土台となる汎用ジョブストアの単体テスト。
// documentJobs.ts 自体は db.ts（実 SQLite を開く）を import するためここでは触らず、
// ジョブのライフサイクル（processing→success/failed）と TTL purge をこのモジュールで担保する。

const TTL_MS = 1000;

// run のバックグラウンド実行（Promise の then/catch）が反映されるのを待つ
const settled = () => new Promise((resolve) => setImmediate(resolve));

test("jobStore: 受付直後は processing、run 完了後に success へ遷移し結果を保持する", async () => {
  const store = createJobStore<{ value: string }>(TTL_MS);
  let resolveRun!: (outcome: { value: string }) => void;
  const jobId = store.create(() => new Promise((resolve) => (resolveRun = resolve)));

  assert.deepEqual(store.get(jobId), { status: "processing" });

  resolveRun({ value: "done" });
  await settled();
  assert.deepEqual(store.get(jobId), { status: "success", value: "done" });
});

test("jobStore: run が reject したら failed とエラーメッセージを保持する", async () => {
  const store = createJobStore<{ value: string }>(TTL_MS);
  const jobId = store.create(() => Promise.reject(new Error("boom")));

  await settled();
  assert.deepEqual(store.get(jobId), { status: "failed", error: "boom" });
});

test("jobStore: 未知の jobId は null（HTTP 404 相当）", () => {
  const store = createJobStore<{ value: string }>(TTL_MS);
  assert.equal(store.get("no-such-job"), null);
});

test("jobStore: settled なジョブは TTL 超過で purge され null になる", async () => {
  const store = createJobStore<{ value: string }>(TTL_MS);
  const jobId = store.create(() => Promise.resolve({ value: "done" }), 0);
  await settled();

  // TTL ちょうどはまだ保持、超過で purge
  assert.deepEqual(store.get(jobId, TTL_MS), { status: "success", value: "done" });
  assert.equal(store.get(jobId, TTL_MS + 1), null);
});

test("jobStore: processing のままのジョブは TTL を超えても purge されない", () => {
  const store = createJobStore<{ value: string }>(TTL_MS);
  const jobId = store.create(() => new Promise(() => {}), 0);

  assert.deepEqual(store.get(jobId, TTL_MS * 100), { status: "processing" });
});
