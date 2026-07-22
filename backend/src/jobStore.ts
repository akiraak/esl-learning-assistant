import crypto from "crypto";

// 汎用の非同期ジョブストア（単一プロセスのメモリ上 Map）。Cloudflare の 100 秒タイムアウト
// （HTTP 524）を避けたい長時間 API を「受付→ポーリング」に分けるための小さな仕組み。
// DB やネットワークに依存しないので単体テストはこのモジュールを直接対象にする。

export type JobState<Outcome extends object> =
  | { status: "processing" }
  | ({ status: "success" } & Outcome)
  | { status: "failed"; error: string };

interface JobEntry<Outcome extends object> {
  state: JobState<Outcome>;
  createdAtMs: number;
}

export interface JobStore<Outcome extends object> {
  /// ジョブを登録して即座に jobId を返し、run はバックグラウンドで実行する。
  create(run: () => Promise<Outcome>, nowMs?: number): string;
  /// ジョブの現在状態を返す。未知の jobId・TTL 超過で purge 済みなら null（HTTP 404 相当）。
  get(jobId: string, nowMs?: number): JobState<Outcome> | null;
}

/// ttlMs: ジョブの保持期間（作成時刻起点）。settled（success/failed）になったジョブだけを
/// 期限切れで削除する。processing のままのジョブは purge しない（いずれ settled になる。
/// エントリ1件は微小で、処理中に消えて GET が 404 になる事故のほうが害が大きい）。
export function createJobStore<Outcome extends object>(ttlMs: number): JobStore<Outcome> {
  const jobs = new Map<string, JobEntry<Outcome>>();

  function purgeExpired(nowMs: number): void {
    for (const [jobId, entry] of jobs) {
      if (entry.state.status !== "processing" && nowMs - entry.createdAtMs > ttlMs) {
        jobs.delete(jobId);
      }
    }
  }

  return {
    create(run: () => Promise<Outcome>, nowMs: number = Date.now()): string {
      purgeExpired(nowMs);
      const jobId = crypto.randomUUID();
      jobs.set(jobId, { state: { status: "processing" }, createdAtMs: nowMs });

      void run()
        .then((outcome) => {
          jobs.set(jobId, { state: { status: "success", ...outcome }, createdAtMs: nowMs });
        })
        .catch((error: unknown) => {
          const message = error instanceof Error ? error.message : String(error);
          jobs.set(jobId, { state: { status: "failed", error: message }, createdAtMs: nowMs });
        });

      return jobId;
    },

    get(jobId: string, nowMs: number = Date.now()): JobState<Outcome> | null {
      purgeExpired(nowMs);
      return jobs.get(jobId)?.state ?? null;
    },
  };
}
