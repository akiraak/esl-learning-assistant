// モデルごとの100万トークンあたり単価（USD）。Anthropicの価格改定に追従が必要。
// 参照: https://platform.claude.com/docs/en/pricing
const PRICING_PER_MILLION_TOKENS: Record<string, { input: number; output: number }> = {
  "claude-sonnet-5": { input: 3.0, output: 15.0 },
  "claude-opus-4-8": { input: 5.0, output: 25.0 },
  "claude-haiku-4-5": { input: 1.0, output: 5.0 },
};

export function estimateCostUsd(model: string, inputTokens: number, outputTokens: number): number {
  const pricing = PRICING_PER_MILLION_TOKENS[model];
  if (!pricing) return 0;
  return (inputTokens * pricing.input + outputTokens * pricing.output) / 1_000_000;
}
