import { config } from "./config";

export type VoiceKey = "chobi" | "naruko";
export type ModelKey = "flash" | "pro";

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

// flash = 低レイテンシ、pro = より高音質（Google公式のGemini TTSモデル）
export const MODEL_PRESETS: Record<ModelKey, string> = {
  flash: "gemini-2.5-flash-preview-tts",
  pro: "gemini-2.5-pro-preview-tts",
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
  candidates?: Array<{ content?: { parts?: Array<{ inlineData?: { data?: string } }> } }>;
}

function extractAudioB64(json: GeminiResponse): string | undefined {
  const parts = json.candidates?.[0]?.content?.parts ?? [];
  for (const part of parts) {
    if (part.inlineData?.data) return part.inlineData.data;
  }
  return undefined;
}

export async function synthesizeSpeech(text: string, voiceKey: VoiceKey, modelKey: ModelKey): Promise<Buffer> {
  if (!config.geminiApiKey) {
    throw new Error("GEMINI_API_KEY is not set");
  }

  const preset = VOICE_PRESETS[voiceKey];
  const model = MODEL_PRESETS[modelKey];
  const endpoint = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`;
  const body = {
    contents: [{ parts: [{ text: `${preset.style}: ${text}` }] }],
    generationConfig: {
      responseModalities: ["AUDIO"],
      speechConfig: { voiceConfig: { prebuiltVoiceConfig: { voiceName: preset.voiceName } } },
    },
  };

  const response = await fetch(endpoint, {
    method: "POST",
    headers: { "content-type": "application/json", "x-goog-api-key": config.geminiApiKey },
    body: JSON.stringify(body),
  });

  if (!response.ok) {
    const errorText = await response.text().catch(() => "");
    throw new Error(`gemini tts HTTP ${response.status}: ${errorText.slice(0, 200)}`);
  }

  const json = (await response.json()) as GeminiResponse;
  const base64Audio = extractAudioB64(json);
  if (!base64Audio) {
    throw new Error("gemini tts: response has no inlineData (audio)");
  }

  return pcmToWav(Buffer.from(base64Audio, "base64"));
}
