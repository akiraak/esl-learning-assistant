export interface ModelPricing {
  input: number;
  output: number;
}

export type PricingTable = Record<string, ModelPricing>;

// モデルごとの100万トークンあたり単価（USD）の既定値。
// pricingSync.ts が LiteLLM の価格JSONから自動更新するため、これは
// 外部ソースが取得できない・値が壊れている場合のフォールバック。
// 参照: https://platform.claude.com/docs/en/pricing
export const DEFAULT_PRICING: PricingTable = {
  "claude-sonnet-5": { input: 3.0, output: 15.0 },
  "claude-opus-4-8": { input: 5.0, output: 25.0 },
  "claude-haiku-4-5": { input: 1.0, output: 5.0 },
};

// 検証ガード: 既定値からの乖離がこの倍率を超える取得値は壊れているとみなして採用しない
const MAX_DEVIATION_FACTOR = 10;

// 採用中の単価表（自動更新でプロセス内のこの値だけが書き換わる。再起動不要）
let currentPricing: PricingTable = structuredClone(DEFAULT_PRICING);

export function estimateCostUsd(model: string, inputTokens: number, outputTokens: number): number {
  const pricing = currentPricing[model];
  if (!pricing) return 0;
  return (inputTokens * pricing.input + outputTokens * pricing.output) / 1_000_000;
}

export function getCurrentPricing(): PricingTable {
  return structuredClone(currentPricing);
}

function validatePrice(value: unknown, defaultValue: number): value is number {
  if (typeof value !== "number" || !Number.isFinite(value) || value <= 0) return false;
  return value <= defaultValue * MAX_DEVIATION_FACTOR && value >= defaultValue / MAX_DEVIATION_FACTOR;
}

export interface ApplyPricingResult {
  // 検証を通って採用した単価表（対象全モデル分。ガードに落ちたモデルは既定値/現行値を維持）
  pricing: PricingTable;
  // ガードに落ちた・ソースに無かったモデルと理由（失敗ログ用）
  rejected: { model: string; reason: string }[];
}

/// LiteLLM の価格JSON（per-token 単価）から対象モデルを抽出し、per-1M に変換・検証して
/// currentPricing に反映する。ガードに落ちたモデルは現行値のまま維持する。
export function applyFetchedPricing(rawJson: unknown): ApplyPricingResult {
  if (typeof rawJson !== "object" || rawJson === null) {
    throw new Error("価格JSONがオブジェクトではありません");
  }
  const source = rawJson as Record<string, { input_cost_per_token?: unknown; output_cost_per_token?: unknown }>;

  const next = getCurrentPricing();
  const rejected: { model: string; reason: string }[] = [];

  for (const model of Object.keys(DEFAULT_PRICING)) {
    const entry = source[model];
    if (!entry || typeof entry !== "object") {
      rejected.push({ model, reason: "ソースにエントリなし" });
      continue;
    }
    const input =
      typeof entry.input_cost_per_token === "number" ? entry.input_cost_per_token * 1_000_000 : NaN;
    const output =
      typeof entry.output_cost_per_token === "number" ? entry.output_cost_per_token * 1_000_000 : NaN;
    if (!validatePrice(input, DEFAULT_PRICING[model].input) || !validatePrice(output, DEFAULT_PRICING[model].output)) {
      rejected.push({
        model,
        reason: `検証ガードに不合格 (input=$${String(entry.input_cost_per_token)}/token, output=$${String(entry.output_cost_per_token)}/token)`,
      });
      continue;
    }
    next[model] = { input, output };
  }

  currentPricing = next;
  return { pricing: structuredClone(next), rejected };
}

/// pricing_state に保存済みの単価表（per-1M）を復元する。検証ガードを通ったモデルだけ採用する。
export function restorePricing(saved: PricingTable): void {
  const next = getCurrentPricing();
  for (const model of Object.keys(DEFAULT_PRICING)) {
    const entry = saved[model];
    if (
      entry &&
      validatePrice(entry.input, DEFAULT_PRICING[model].input) &&
      validatePrice(entry.output, DEFAULT_PRICING[model].output)
    ) {
      next[model] = { input: entry.input, output: entry.output };
    }
  }
  currentPricing = next;
}
