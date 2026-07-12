import { config } from "./config";

// Gemini がインライン（generateContent の inlineData）で受け付ける音声形式。
// これ以外は事前に 400 で弾く（m4a/mp4 コンテナは inline 非対応のため v1 では対象外。
// iOS 側での変換対応は将来拡張）。参照: https://ai.google.dev/gemini-api/docs/audio
// mimeType→保存拡張子の対応も兼ねる。
export const SUPPORTED_AUDIO_MIME_EXTENSIONS: Record<string, string> = {
  "audio/wav": "wav",
  "audio/mp3": "mp3",
  "audio/mpeg": "mp3",
  "audio/aac": "aac",
  "audio/aiff": "aiff",
  "audio/ogg": "ogg",
  "audio/flac": "flac",
};

export function isSupportedAudioMimeType(mimeType: unknown): mimeType is string {
  return typeof mimeType === "string" && mimeType in SUPPORTED_AUDIO_MIME_EXTENSIONS;
}

interface GeminiTranscribeResponse {
  candidates?: Array<{
    finishReason?: string;
    content?: { parts?: Array<{ text?: string }> };
  }>;
  usageMetadata?: { promptTokenCount?: number; candidatesTokenCount?: number };
}

export interface TranscriptionResult {
  englishText: string;
  inputTokens: number;
  outputTokens: number;
}

const TRANSCRIBE_RETRIES = 3;
// 音声アップロード＋文字起こしは分単位でかかりうるため TTS より長めに取る。
const TRANSCRIBE_TIMEOUT_MS = 180_000;
// gemini-2.5-flash は思考が既定で有効。文字起こしに思考は不要でコスト・レイテンシの無駄なので切る。
const THINKING_BUDGET = 0;
// 15分程度の音声でも全文がテキスト出力に収まるよう上限を大きく取る。
const MAX_OUTPUT_TOKENS = 65536;

const TRANSCRIBE_PROMPT =
  "Transcribe the spoken English in this audio verbatim. " +
  "Output only the transcription as plain text with natural sentence punctuation. " +
  "Break the transcription into short paragraphs of roughly 2-4 sentences, " +
  "starting a new paragraph whenever the topic or speaker changes, " +
  "and separate paragraphs with a blank line. " +
  "Do not add any commentary, labels, speaker names, or timestamps.";

// プロンプトは 2〜4 文/段落を指示するが、モデルが長い塊を返した場合の保険として
// これを超える段落は SENTENCES_PER_CHUNK 文ごとに再分割する。
const MAX_SENTENCES_PER_PARAGRAPH = 5;
const SENTENCES_PER_CHUNK = 3;

// 直後に大文字の固有名詞が続くため文境界と誤判定しやすい敬称等の略語
const NON_BOUNDARY_ABBREVIATIONS = new Set(["Mr", "Mrs", "Ms", "Dr", "Prof", "St", "Jr", "Sr", "vs", "etc"]);

/// `.!?`（+閉じ引用符）の後に空白と大文字/数字が続く位置を文境界と見なすヒューリスティック
function splitSentences(paragraph: string): string[] {
  const sentences: string[] = [];
  let start = 0;
  const boundary = /[.!?]+["'”’)]*\s+(?=["'“‘(]*[A-Z0-9])/g;
  let match: RegExpExecArray | null;
  while ((match = boundary.exec(paragraph)) !== null) {
    const candidate = paragraph.slice(start, match.index + match[0].length).trim();
    const lastWord = candidate.match(/([A-Za-z]+)\.["'”’)]*$/)?.[1];
    if (lastWord && NON_BOUNDARY_ABBREVIATIONS.has(lastWord)) continue;
    sentences.push(candidate);
    start = match.index + match[0].length;
  }
  const rest = paragraph.slice(start).trim();
  if (rest) sentences.push(rest);
  return sentences;
}

/// Gemini 出力の段落構造を「空行 = 段落境界」に正規化する。iOS の MarkdownLite は
/// 空行だけを段落境界と見なす（単一改行はスペース連結で1段落に潰す）ため、
/// 単一改行のみの出力や改行ゼロの長文をそのまま返すとベタ表示になる。
export function formatTranscriptParagraphs(text: string): string {
  const paragraphs = text
    .replace(/\r\n?/g, "\n")
    .split(/\n+/)
    .map((line) => line.trim())
    .filter((line) => line.length > 0);

  const chunked = paragraphs.flatMap((paragraph) => {
    const sentences = splitSentences(paragraph);
    if (sentences.length <= MAX_SENTENCES_PER_PARAGRAPH) return [paragraph];
    const chunks: string[] = [];
    for (let i = 0; i < sentences.length; i += SENTENCES_PER_CHUNK) {
      chunks.push(sentences.slice(i, i + SENTENCES_PER_CHUNK).join(" "));
    }
    return chunks;
  });

  return chunked.join("\n\n");
}

/// 音声（base64）を Gemini に投げて英文文字起こしを得る。tts.ts の synthesizeChunk を
/// 「音声出力」から「音声入力＋テキスト出力」に反転したもの。fetch/リトライ/timeout/
/// usageMetadata 抽出は同じ作法。
export async function transcribeAudio(audioBase64: string, mimeType: string): Promise<TranscriptionResult> {
  if (!config.geminiApiKey) {
    throw new Error("GEMINI_API_KEY is not set");
  }

  const model = config.transcriptionModel;
  const endpoint = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`;
  const body = {
    contents: [
      {
        parts: [{ inlineData: { mimeType, data: audioBase64 } }, { text: TRANSCRIBE_PROMPT }],
      },
    ],
    generationConfig: {
      temperature: 0,
      maxOutputTokens: MAX_OUTPUT_TOKENS,
      thinkingConfig: { thinkingBudget: THINKING_BUDGET },
    },
  };

  let lastError = "";
  for (let attempt = 1; attempt <= TRANSCRIBE_RETRIES; attempt++) {
    try {
      const response = await fetch(endpoint, {
        method: "POST",
        headers: { "content-type": "application/json", "x-goog-api-key": config.geminiApiKey },
        body: JSON.stringify(body),
        signal: AbortSignal.timeout(TRANSCRIBE_TIMEOUT_MS),
      });

      if (!response.ok) {
        const errorText = await response.text().catch(() => "");
        lastError = `HTTP ${response.status}: ${errorText.slice(0, 200)}`;
        // 4xx はリトライしても結果が変わらないため即時失敗させる（429は除く）
        if (response.status >= 400 && response.status < 500 && response.status !== 429) break;
        continue;
      }

      const json = (await response.json()) as GeminiTranscribeResponse;
      const candidate = json.candidates?.[0];
      const finishReason = candidate?.finishReason;
      const text = (candidate?.content?.parts ?? [])
        .map((p) => p.text ?? "")
        .join("")
        .trim();

      if (!text) {
        lastError = `no text in response (finishReason=${finishReason ?? "unknown"})`;
        continue;
      }
      // STOP 以外（MAX_TOKENS/SAFETY 等）は途中打ち切りの可能性が高いのでリトライ扱い
      if (finishReason && finishReason !== "STOP") {
        lastError = `finishReason=${finishReason}`;
        continue;
      }
      return {
        englishText: formatTranscriptParagraphs(text),
        inputTokens: json.usageMetadata?.promptTokenCount ?? 0,
        outputTokens: json.usageMetadata?.candidatesTokenCount ?? 0,
      };
    } catch (error) {
      lastError = error instanceof Error ? error.message : String(error);
    }
  }
  throw new Error(`gemini transcribe: failed after ${TRANSCRIBE_RETRIES} attempts: ${lastError}`);
}
