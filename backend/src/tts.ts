import { config } from "./config";

export type VoiceKey = "chobi" | "naruko";
export type ModelKey = "flash" | "pro" | "flash31";

interface VoicePreset {
  voiceName: string;
  style: string;
}

// claude-code-manager (ai-monitor/voice-persona.json) の声（prebuilt voice名）とキャラクター性を流用。
// スタイル指示は読み上げるOCR本文（英語）と言語を合わせないと発音が引きずられるため英語にしている。
export const VOICE_PRESETS: Record<VoiceKey, VoicePreset> = {
  chobi: {
    voiceName: "Leda",
    style: "Read the following in a warm, gently cheerful, smiling tone",
  },
  naruko: {
    voiceName: "Aoede",
    style: "Read the following in an energetic, bright voice full of curiosity",
  },
};

// flash31 = 現行の既定（Gemini 3.1世代、全読み上げ箇所で使用）。
// flash / pro は 2.5 世代の旧キー。旧iOSクライアントからのリクエスト受付と、
// tts_audio の既存行（model 列に tier キーで保存）のモデルID読み替えのために残している。
export const MODEL_PRESETS: Record<ModelKey, string> = {
  flash: "gemini-2.5-flash-preview-tts",
  pro: "gemini-2.5-pro-preview-tts",
  flash31: "gemini-3.1-flash-tts-preview",
};

const SAMPLE_RATE = 24000;
const CHANNELS = 1;
const BITS = 16;

function pcmToWav(pcm: Buffer): Buffer {
  const blockAlign = (CHANNELS * BITS) >> 3;
  const byteRate = SAMPLE_RATE * blockAlign;
  const header = Buffer.alloc(44);
  header.write("RIFF", 0);
  header.writeUInt32LE(36 + pcm.length, 4);
  header.write("WAVE", 8);
  header.write("fmt ", 12);
  header.writeUInt32LE(16, 16);
  header.writeUInt16LE(1, 20);
  header.writeUInt16LE(CHANNELS, 22);
  header.writeUInt32LE(SAMPLE_RATE, 24);
  header.writeUInt32LE(byteRate, 28);
  header.writeUInt16LE(blockAlign, 32);
  header.writeUInt16LE(BITS, 34);
  header.write("data", 36);
  header.writeUInt32LE(pcm.length, 40);
  return Buffer.concat([header, pcm]);
}

interface GeminiResponse {
  candidates?: Array<{
    finishReason?: string;
    content?: { parts?: Array<{ inlineData?: { data?: string } }> };
  }>;
  usageMetadata?: { promptTokenCount?: number; candidatesTokenCount?: number };
}

interface ChunkResult {
  pcm: Buffer;
  inputTokens: number;
  outputTokens: number;
}

// 長文を一括で投げると finishReason=OTHER / HTTP 500 / STOPなのに音声が途中で切れる
// サイレント打ち切りが散発する（docs/plans/tts-long-text.md の実測結果参照）ため、
// 文境界でチャンクに分割し、チャンクごとに合成してPCMを連結する。
const CHUNK_MAX_CHARS = 1500;
const CHUNK_RETRIES = 3;
const CHUNK_TIMEOUT_MS = 120_000;
const CHUNK_CONCURRENCY = 3;
// 英語の読み上げは実測 10〜13 chars/s 程度。これを大幅に超える＝音声が短すぎる＝打ち切りとみなす。
const TRUNCATION_CHARS_PER_SEC = 30;

export function splitTextIntoChunks(text: string, maxChars: number = CHUNK_MAX_CHARS): string[] {
  const sentences = text.split(/(?<=[.!?！？。…])\s+|\n+/).filter((s) => s.trim().length > 0);
  const chunks: string[] = [];
  let current = "";

  const push = () => {
    if (current.trim()) chunks.push(current.trim());
    current = "";
  };

  for (const sentence of sentences) {
    if (sentence.length > maxChars) {
      // 1文が上限を超える場合は単語境界で強制分割する
      push();
      const words = sentence.split(/\s+/);
      for (const word of words) {
        if (word.length > maxChars) {
          // 空白を含まない超長トークンは文字数でハード分割する
          push();
          for (let i = 0; i < word.length; i += maxChars) {
            chunks.push(word.slice(i, i + maxChars));
          }
          continue;
        }
        if (current.length + word.length + 1 > maxChars) push();
        current += (current ? " " : "") + word;
      }
      push();
      continue;
    }
    if (current.length + sentence.length + 1 > maxChars) push();
    current += (current ? " " : "") + sentence;
  }
  push();
  return chunks;
}

async function synthesizeChunk(chunk: string, preset: VoicePreset, model: string): Promise<ChunkResult> {
  const endpoint = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`;
  const body = {
    contents: [{ parts: [{ text: `${preset.style}: ${chunk}` }] }],
    generationConfig: {
      responseModalities: ["AUDIO"],
      speechConfig: { voiceConfig: { prebuiltVoiceConfig: { voiceName: preset.voiceName } } },
    },
  };

  let lastError = "";
  for (let attempt = 1; attempt <= CHUNK_RETRIES; attempt++) {
    try {
      const response = await fetch(endpoint, {
        method: "POST",
        headers: { "content-type": "application/json", "x-goog-api-key": config.geminiApiKey },
        body: JSON.stringify(body),
        signal: AbortSignal.timeout(CHUNK_TIMEOUT_MS),
      });

      if (!response.ok) {
        const errorText = await response.text().catch(() => "");
        lastError = `HTTP ${response.status}: ${errorText.slice(0, 200)}`;
        // 4xx はリトライしても結果が変わらないため即時失敗させる（429は除く）
        if (response.status >= 400 && response.status < 500 && response.status !== 429) break;
        continue;
      }

      const json = (await response.json()) as GeminiResponse;
      const candidate = json.candidates?.[0];
      const finishReason = candidate?.finishReason;
      const parts = candidate?.content?.parts ?? [];
      const pcmBuffers = parts
        .filter((p) => p.inlineData?.data)
        .map((p) => Buffer.from(p.inlineData!.data!, "base64"));
      const pcm = Buffer.concat(pcmBuffers);

      if (pcm.length === 0) {
        lastError = `no audio in response (finishReason=${finishReason ?? "unknown"})`;
        continue;
      }
      if (finishReason && finishReason !== "STOP") {
        lastError = `finishReason=${finishReason}`;
        continue;
      }
      // STOPでも音声が途中で切れることがあるため、読み上げ速度で打ち切りを検知する
      const seconds = pcm.length / (SAMPLE_RATE * (BITS >> 3) * CHANNELS);
      if (chunk.length > 300 && chunk.length / seconds > TRUNCATION_CHARS_PER_SEC) {
        lastError = `audio too short (${seconds.toFixed(1)}s for ${chunk.length} chars) — likely truncated`;
        continue;
      }
      return {
        pcm,
        inputTokens: json.usageMetadata?.promptTokenCount ?? 0,
        outputTokens: json.usageMetadata?.candidatesTokenCount ?? 0,
      };
    } catch (error) {
      lastError = error instanceof Error ? error.message : String(error);
    }
  }
  throw new Error(`gemini tts: chunk failed after ${CHUNK_RETRIES} attempts: ${lastError}`);
}

export interface SynthesisResult {
  wav: Buffer;
  // 全チャンクの合算（リトライで失敗した試行分は計上しない割り切り）
  inputTokens: number;
  outputTokens: number;
}

export async function synthesizeSpeech(text: string, voiceKey: VoiceKey, modelKey: ModelKey): Promise<SynthesisResult> {
  if (!config.geminiApiKey) {
    throw new Error("GEMINI_API_KEY is not set");
  }

  const preset = VOICE_PRESETS[voiceKey];
  const model = MODEL_PRESETS[modelKey];
  // チャンクは独立に合成できるため並列化してレイテンシを抑える（結合順は元の順序を維持）
  const chunks = splitTextIntoChunks(text);
  const results: ChunkResult[] = new Array(chunks.length);
  let nextIndex = 0;
  const workers = Array.from({ length: Math.min(CHUNK_CONCURRENCY, chunks.length) }, async () => {
    while (nextIndex < chunks.length) {
      const index = nextIndex++;
      results[index] = await synthesizeChunk(chunks[index], preset, model);
    }
  });
  await Promise.all(workers);
  return {
    wav: pcmToWav(Buffer.concat(results.map((r) => r.pcm))),
    inputTokens: results.reduce((sum, r) => sum + r.inputTokens, 0),
    outputTokens: results.reduce((sum, r) => sum + r.outputTokens, 0),
  };
}
