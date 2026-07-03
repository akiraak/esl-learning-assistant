import { config } from "./config";

// OpenAI の画像生成モデル（https://developers.openai.com/api/docs/models/gpt-image-2）。
// 料金はトークン単価制（pricing.ts の DEFAULT_IMAGE_PRICING）で、レスポンスの usage から算出する。
export const ILLUSTRATION_MODEL = "gpt-image-2";

// 単語詳細のインライン表示用途なので正方形1枚・最低品質で固定する
// （low 1024x1024 でおおよそ $0.006/枚）。
const IMAGE_SIZE = "1024x1024";
const IMAGE_QUALITY = "low";

const REQUEST_TIMEOUT_MS = 120_000;
const REQUEST_RETRIES = 3;

/// 生成プロンプト（docs/plans/word-illustration-generation.md のテンプレート）。
/// 語義・例文は words.word_info_json から取れた場合のみ含める（無ければ単語のみで組み立てる）。
export function buildIllustrationPrompt(word: string, definition?: string, exampleSentence?: string): string {
  const parts = [
    `A simple flat-style educational illustration that intuitively conveys the meaning of ` +
      `the English word "${word}"${definition ? ` (${definition})` : ""}.`,
  ];
  if (exampleSentence) {
    parts.push(`Depict a single clear scene based on this example: "${exampleSentence}".`);
  }
  parts.push(
    "Clean vector art, soft colors, plain light background. " +
      "Absolutely no text, letters, or numbers anywhere in the image."
  );
  return parts.join(" ");
}

interface ImagesResponse {
  data?: Array<{ b64_json?: string }>;
  usage?: {
    input_tokens?: number;
    output_tokens?: number;
  };
}

export interface IllustrationResult {
  png: Buffer;
  inputTokens: number;
  outputTokens: number;
}

/// OpenAI Images API で PNG を1枚生成する。tts.ts と同様に raw fetch + リトライで呼ぶ
/// （4xx はリトライしても結果が変わらないため 429 を除き即時失敗させる）。
export async function generateIllustration(prompt: string): Promise<IllustrationResult> {
  if (!config.openaiApiKey) {
    throw new Error("OPENAI_API_KEY is not set");
  }

  const body = {
    model: ILLUSTRATION_MODEL,
    prompt,
    size: IMAGE_SIZE,
    quality: IMAGE_QUALITY,
    n: 1,
  };

  let lastError = "";
  for (let attempt = 1; attempt <= REQUEST_RETRIES; attempt++) {
    try {
      const response = await fetch("https://api.openai.com/v1/images/generations", {
        method: "POST",
        headers: {
          "content-type": "application/json",
          authorization: `Bearer ${config.openaiApiKey}`,
        },
        body: JSON.stringify(body),
        signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
      });

      if (!response.ok) {
        const errorText = await response.text().catch(() => "");
        lastError = `HTTP ${response.status}: ${errorText.slice(0, 300)}`;
        if (response.status >= 400 && response.status < 500 && response.status !== 429) break;
        continue;
      }

      const json = (await response.json()) as ImagesResponse;
      const b64 = json.data?.[0]?.b64_json;
      if (!b64) {
        lastError = "no image in response";
        continue;
      }
      return {
        png: Buffer.from(b64, "base64"),
        inputTokens: json.usage?.input_tokens ?? 0,
        outputTokens: json.usage?.output_tokens ?? 0,
      };
    } catch (error) {
      lastError = error instanceof Error ? error.message : String(error);
    }
  }
  throw new Error(`openai images: failed after ${REQUEST_RETRIES} attempts: ${lastError}`);
}
