// Gemini 3.1 TTS の疎通・互換性検証スクリプト（docs/plans/gemini-3-1-tts-verification.md Phase 1）
// 現行 tts.ts と同じ generateContent リクエスト形式が 3.1 でそのまま通るかを確認する。
// DB には書き込まない（未知モデルの cost_usd $0 焼き込みを避けるため synthesizeSpeech 経由にしない）。
// 使い方: npx ts-node scripts/tts-gemini31-check.ts [モデルID] [WAV出力ディレクトリ]
import "dotenv/config";
import fs from "fs";
import path from "path";
import { splitTextIntoChunks, VOICE_PRESETS, type VoiceKey } from "../src/tts";

const MODEL = process.argv[2] ?? "gemini-3.1-flash-tts-preview";
const OUT_DIR = process.argv[3] ?? "/tmp";
// 公称単価（per 1M tokens）: input $1.00 / output $20.00
const PRICE_IN = 1.0;
const PRICE_OUT = 20.0;

const SAMPLE_RATE = 24000;

interface GeminiResponse {
  candidates?: Array<{
    finishReason?: string;
    content?: { parts?: Array<{ inlineData?: { data?: string; mimeType?: string } }> };
  }>;
  usageMetadata?: { promptTokenCount?: number; candidatesTokenCount?: number };
}

function pcmToWav(pcm: Buffer): Buffer {
  const header = Buffer.alloc(44);
  header.write("RIFF", 0);
  header.writeUInt32LE(36 + pcm.length, 4);
  header.write("WAVE", 8);
  header.write("fmt ", 12);
  header.writeUInt32LE(16, 16);
  header.writeUInt16LE(1, 20);
  header.writeUInt16LE(1, 22);
  header.writeUInt32LE(SAMPLE_RATE, 24);
  header.writeUInt32LE(SAMPLE_RATE * 2, 28);
  header.writeUInt16LE(2, 32);
  header.writeUInt16LE(16, 34);
  header.write("data", 36);
  header.writeUInt32LE(pcm.length, 40);
  return Buffer.concat([header, pcm]);
}

async function callOnce(label: string, text: string, voiceKey: VoiceKey): Promise<Buffer> {
  const preset = VOICE_PRESETS[voiceKey];
  const endpoint = `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent`;
  const body = {
    contents: [{ parts: [{ text: `${preset.style}: ${text}` }] }],
    generationConfig: {
      responseModalities: ["AUDIO"],
      speechConfig: { voiceConfig: { prebuiltVoiceConfig: { voiceName: preset.voiceName } } },
    },
  };
  const started = Date.now();
  const response = await fetch(endpoint, {
    method: "POST",
    headers: { "content-type": "application/json", "x-goog-api-key": process.env.GEMINI_API_KEY ?? "" },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(120_000),
  });
  const latencyMs = Date.now() - started;
  if (!response.ok) {
    const errorText = await response.text().catch(() => "");
    throw new Error(`[${label}] HTTP ${response.status}: ${errorText.slice(0, 500)}`);
  }
  const json = (await response.json()) as GeminiResponse;
  const candidate = json.candidates?.[0];
  const parts = candidate?.content?.parts ?? [];
  const mimeTypes = [...new Set(parts.map((p) => p.inlineData?.mimeType).filter(Boolean))];
  const pcm = Buffer.concat(
    parts.filter((p) => p.inlineData?.data).map((p) => Buffer.from(p.inlineData!.data!, "base64"))
  );
  const seconds = pcm.length / (SAMPLE_RATE * 2);
  const inTok = json.usageMetadata?.promptTokenCount ?? 0;
  const outTok = json.usageMetadata?.candidatesTokenCount ?? 0;
  const cost = (inTok * PRICE_IN + outTok * PRICE_OUT) / 1_000_000;
  console.log(
    `[${label}] chars=${text.length} voice=${preset.voiceName} finishReason=${candidate?.finishReason} ` +
      `mime=${mimeTypes.join(",") || "(none)"} pcmBytes=${pcm.length} audioSec=${seconds.toFixed(1)} ` +
      `charsPerSec=${seconds > 0 ? (text.length / seconds).toFixed(1) : "-"} ` +
      `tokens=in:${inTok}/out:${outTok} cost=$${cost.toFixed(5)} latencyMs=${latencyMs}`
  );
  if (pcm.length === 0) throw new Error(`[${label}] no audio in response`);
  return pcm;
}

const WORD = "serendipity";
const SENTENCE = "She discovered the quaint bookstore by pure serendipity while wandering the old town.";
// 学習テキストに角括弧が含まれるケース（3.1 の音声タグ [whispers] 等が誤発動しないかの聴感確認用）
const BRACKETS =
  "The results [see Figure 2] were significant. He wrote [sic] in the margin, and the list included [1] apples and [2] oranges.";
const PASSAGE_BASE =
  "The little fox trotted along the winding forest path, pausing now and then to sniff the cool morning air. " +
  "Sunlight filtered through the tall pine trees, painting golden patterns on the soft carpet of fallen needles. " +
  "Far away, a woodpecker tapped a steady rhythm, and the stream murmured quietly over smooth gray stones. ";

async function main() {
  if (!process.env.GEMINI_API_KEY) throw new Error("GEMINI_API_KEY is not set");
  console.log(`model=${MODEL} outDir=${OUT_DIR}`);

  const cases: Array<{ label: string; text: string; voice: VoiceKey }> = [
    { label: "word", text: WORD, voice: "chobi" },
    { label: "sentence", text: SENTENCE, voice: "naruko" },
    { label: "brackets", text: BRACKETS, voice: "chobi" },
  ];
  for (const c of cases) {
    const pcm = await callOnce(c.label, c.text, c.voice);
    const file = path.join(OUT_DIR, `tts31-${c.label}.wav`);
    fs.writeFileSync(file, pcmToWav(pcm));
    console.log(`  saved: ${file}`);
  }

  // 長文: 現行のチャンク分割（1500字）で複数チャンクになる長さを合成し、連結して1本のWAVにする
  let passage = "";
  let i = 0;
  while (passage.length < 2600) passage += PASSAGE_BASE.replace("little fox", `little fox number ${++i}`);
  const chunks = splitTextIntoChunks(passage);
  console.log(`[passage] chars=${passage.length} chunks=${chunks.length}`);
  const pcms: Buffer[] = [];
  for (let idx = 0; idx < chunks.length; idx++) {
    pcms.push(await callOnce(`passage-chunk${idx + 1}`, chunks[idx], "chobi"));
  }
  const file = path.join(OUT_DIR, "tts31-passage.wav");
  fs.writeFileSync(file, pcmToWav(Buffer.concat(pcms)));
  console.log(`  saved: ${file}`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
