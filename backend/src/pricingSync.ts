import { getPricingState, insertSystemLog, savePricingState } from "./db";
import {
  applyFetchedPricing,
  applyFetchedTtsPricing,
  getCurrentPricing,
  restorePricing,
  type ApplyPricingResult,
  type PricingTable,
} from "./pricing";
import { logger } from "./logger";

// LiteLLM がコミュニティ管理している機械可読の価格表（Anthropic に公式の価格APIは無い）
const PRICING_SOURCE_URL =
  "https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json";
// Gemini TTS の取得元は Google 公式の料金ページ。LiteLLM は TTS モデルに誤った単価を
// 載せており（pricing.ts の DEFAULT_TTS_PRICING 参照）取得元にできない。
// 言語指定が無いと機械翻訳版（"Input price" ラベルが訳される）がランダムに返るため、
// ?hl=en と Accept-Language で英語版を固定する。
const TTS_PRICING_SOURCE_URL = "https://ai.google.dev/gemini-api/docs/pricing?hl=en";
const FETCH_TIMEOUT_MS = 30_000;
const SYNC_INTERVAL_MS = Number(process.env.PRICING_SYNC_INTERVAL_MS ?? 24 * 60 * 60 * 1000);

const LOG_CATEGORY = "pricing";

/// 前回適用値と比較して「claude-sonnet-5 input $3.00→$2.50」形式の変更一覧を作る
function diffPricing(before: PricingTable, after: PricingTable): string[] {
  const changes: string[] = [];
  for (const model of Object.keys(after)) {
    const prev = before[model];
    const next = after[model];
    if (!prev) {
      changes.push(`${model} 新規 input $${next.input.toFixed(2)} / output $${next.output.toFixed(2)}`);
      continue;
    }
    if (prev.input !== next.input) {
      changes.push(`${model} input $${prev.input.toFixed(2)}→$${next.input.toFixed(2)}`);
    }
    if (prev.output !== next.output) {
      changes.push(`${model} output $${prev.output.toFixed(2)}→$${next.output.toFixed(2)}`);
    }
  }
  return changes;
}

/// 取得→反映→system_logs 記録の共通処理。失敗してもthrowしない
/// （currentPricing は維持され、料金計算は従来値で動き続ける）。
async function runPricingCheck(label: string, apply: () => Promise<ApplyPricingResult>): Promise<void> {
  const before = getCurrentPricing();
  try {
    const result = await apply();

    savePricingState(JSON.stringify(result.pricing));

    const changes = diffPricing(before, result.pricing);
    const rejectedNote = result.rejected.length
      ? `／採用見送り: ${result.rejected.map((r) => `${r.model}（${r.reason}）`).join(", ")}`
      : "";
    if (changes.length > 0) {
      insertSystemLog(
        LOG_CATEGORY,
        "warn",
        `${label}更新チェック: 成功（変更あり: ${changes.join(", ")}）${rejectedNote}`
      );
      logger.warn(`pricing-sync: ${label} prices changed: ${changes.join(", ")}`);
    } else {
      insertSystemLog(LOG_CATEGORY, "info", `${label}更新チェック: 成功（変更なし）${rejectedNote}`);
      logger.info(`pricing-sync: ${label} check ok (no changes)`);
    }
  } catch (error) {
    const reason =
      error instanceof Error && error.name === "TimeoutError"
        ? `タイムアウト（${FETCH_TIMEOUT_MS / 1000}秒）`
        : error instanceof Error
          ? error.message
          : String(error);
    insertSystemLog(LOG_CATEGORY, "error", `${label}更新チェック: 失敗（${reason}）`);
    logger.error(`pricing-sync: ${label} check failed: ${reason}`);
  }
}

/// LiteLLM の価格JSONを取得して Claude モデルの単価表に反映する。
export async function fetchAndApplyPricing(): Promise<void> {
  await runPricingCheck("料金表", async () => {
    const response = await fetch(PRICING_SOURCE_URL, { signal: AbortSignal.timeout(FETCH_TIMEOUT_MS) });
    if (!response.ok) {
      throw new Error(`HTTP ${response.status}`);
    }
    const rawJson = (await response.json()) as unknown;
    return applyFetchedPricing(rawJson);
  });
}

/// Google 公式料金ページを取得して Gemini TTS モデルの単価表に反映する。
export async function fetchAndApplyTtsPricing(): Promise<void> {
  await runPricingCheck("TTS料金表", async () => {
    const response = await fetch(TTS_PRICING_SOURCE_URL, {
      signal: AbortSignal.timeout(FETCH_TIMEOUT_MS),
      headers: { "Accept-Language": "en" },
    });
    if (!response.ok) {
      throw new Error(`HTTP ${response.status}`);
    }
    const html = await response.text();
    return applyFetchedTtsPricing(html);
  });
}

/// 起動時に呼ぶ: pricing_state から前回適用値を復元 → 即時1回チェック → 24時間ごとに繰り返す
export function startPricingSync(): void {
  const state = getPricingState();
  if (state) {
    try {
      restorePricing(JSON.parse(state.prices_json) as PricingTable);
      logger.info(`pricing-sync: restored pricing state from ${state.updated_at}`);
    } catch (error) {
      logger.warn(
        `pricing-sync: failed to restore pricing state, using defaults: ${error instanceof Error ? error.message : String(error)}`
      );
    }
  }

  // 2つのチェックを並行実行すると diff の基準（before）が互いの適用と交錯して
  // 変更ログが二重に出ることがあるため、直列で実行する
  const runAllChecks = async () => {
    await fetchAndApplyPricing();
    await fetchAndApplyTtsPricing();
  };
  void runAllChecks();
  // unref() してこのタイマーがプロセス終了を妨げないようにする
  setInterval(() => void runAllChecks(), SYNC_INTERVAL_MS).unref();
}
