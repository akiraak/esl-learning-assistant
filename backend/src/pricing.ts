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

// Gemini TTS の100万トークンあたり単価（USD）の既定値。LiteLLM の価格JSONはTTSモデルに
// 誤った単価を載せている（2026-07-03 時点: flash $0.30/$2.50, pro $1.25/$10 — いずれも
// 検証ガードを通過してしまう）ため、TTS だけは Google 公式料金ページを取得元に自動更新する。
// 参照: https://ai.google.dev/gemini-api/docs/pricing（2026-07-03 確認）
export const DEFAULT_TTS_PRICING: PricingTable = {
  "gemini-2.5-flash-preview-tts": { input: 0.5, output: 10.0 },
  "gemini-2.5-pro-preview-tts": { input: 1.0, output: 20.0 },
};

// 検証ガード: 既定値からの乖離がこの倍率を超える取得値は壊れているとみなして採用しない
const MAX_DEVIATION_FACTOR = 10;

// 採用中の単価表（自動更新でプロセス内のこの値だけが書き換わる。再起動不要）
let currentPricing: PricingTable = { ...structuredClone(DEFAULT_PRICING), ...structuredClone(DEFAULT_TTS_PRICING) };

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

/// Google 公式料金ページの HTML から Gemini TTS モデルの単価（per 1M tokens）を抽出して
/// currentPricing に反映する。ページのテキスト構造は
///   <セクション見出しにモデルID> … Input price … $0.50 (text) … Output price … $10.00 (audio)
/// という並び。HTMLマークアップの量は配信変種によって大きく揺れる（同一内容でも±2万バイト）
/// ため、タグを除去したテキストに対してセクションを切り出して抽出する。
/// ガードに落ちた・見つからなかったモデルは現行値のまま維持する。
export function applyFetchedTtsPricing(html: string): ApplyPricingResult {
  const text = html.replace(/<[^>]+>/g, " ");
  const next = getCurrentPricing();
  const rejected: { model: string; reason: string }[] = [];

  for (const model of Object.keys(DEFAULT_TTS_PRICING)) {
    const otherModels = Object.keys(DEFAULT_TTS_PRICING).filter((m) => m !== model);
    const section = findTtsPricingSection(text, model, otherModels);
    if (!section) {
      rejected.push({ model, reason: "ページ内に料金セクションが見つからない" });
      continue;
    }
    const input = matchPrice(section, /Input price[\s\S]{0,300}?\$([0-9]+(?:\.[0-9]+)?)\s*\(text\)/);
    const output = matchPrice(section, /Output price[\s\S]{0,300}?\$([0-9]+(?:\.[0-9]+)?)\s*\(audio\)/);
    if (input === null || output === null) {
      rejected.push({ model, reason: "Input/Output price の抽出に失敗" });
      continue;
    }
    if (!validatePrice(input, DEFAULT_TTS_PRICING[model].input) || !validatePrice(output, DEFAULT_TTS_PRICING[model].output)) {
      rejected.push({ model, reason: `検証ガードに不合格 (input=$${input}/1M, output=$${output}/1M)` });
      continue;
    }
    next[model] = { input, output };
  }

  currentPricing = next;
  return { pricing: structuredClone(next), rejected };
}

/// タグ除去済みテキストからモデルIDの料金セクションを切り出す。
/// - 目次やリンクなど料金表を伴わない出現はスキップして次の出現を走査する
/// - 別モデルのIDが先に現れたらそこでセクションを打ち切り、隣のモデルの料金を誤って
///   拾わないようにする（flash と pro のセクションは連続して並んでいるため）
function findTtsPricingSection(text: string, model: string, otherModels: string[]): string | null {
  let from = 0;
  while (true) {
    const idx = text.indexOf(model, from);
    if (idx === -1) return null;
    const start = idx + model.length;
    let end = Math.min(text.length, start + 5000);
    for (const other of otherModels) {
      const otherIdx = text.indexOf(other, start);
      if (otherIdx !== -1 && otherIdx < end) end = otherIdx;
    }
    const section = text.slice(start, end);
    if (section.includes("Input price")) return section;
    from = start;
  }
}

function matchPrice(section: string, pattern: RegExp): number | null {
  const m = section.match(pattern);
  if (!m) return null;
  const value = Number(m[1]);
  return Number.isFinite(value) ? value : null;
}

/// pricing_state に保存済みの単価表（per-1M）を復元する。検証ガードを通ったモデルだけ採用する。
export function restorePricing(saved: PricingTable): void {
  const defaults: PricingTable = { ...DEFAULT_PRICING, ...DEFAULT_TTS_PRICING };
  const next = getCurrentPricing();
  for (const model of Object.keys(defaults)) {
    const entry = saved[model];
    if (
      entry &&
      validatePrice(entry.input, defaults[model].input) &&
      validatePrice(entry.output, defaults[model].output)
    ) {
      next[model] = { input: entry.input, output: entry.output };
    }
  }
  currentPricing = next;
}
