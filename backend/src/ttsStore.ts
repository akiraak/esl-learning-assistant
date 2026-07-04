import fs from "fs";
import path from "path";
import crypto from "crypto";
import { config } from "./config";
import { getTtsAudioByHash, upsertTtsAudio } from "./db";
import { synthesizeSpeech, VOICE_PRESETS, MODEL_PRESETS, type VoiceKey, type ModelKey } from "./tts";
import { estimateCostUsd } from "./pricing";
import { logger } from "./logger";
import type { QuizQuestion } from "./quizQuestions";

export interface TtsAudioResult {
  wav: Buffer;
  /// キャッシュヒット時は 0（新規合成が発生した場合のみ課金）
  costUsd: number;
  cacheHit: boolean;
}

/// 同一 (model, text) は保存済みWAVを返す（Gemini再呼び出しなし）。
/// キャラは初回生成時にランダム選択され、キャッシュにより同一テキストでは固定される。
/// ファイルが欠損していた場合は再合成して自己修復する（その際キャラは選び直し）。
export async function getOrSynthesizeTtsAudio(text: string, model: ModelKey): Promise<TtsAudioResult> {
  const startedAt = Date.now();
  const textHash = crypto.createHash("sha256").update(`${model}|${text}`).digest("hex");
  const cached = getTtsAudioByHash(textHash);
  if (cached) {
    const cachedPath = path.join(config.ttsDir, cached.filename);
    if (fs.existsSync(cachedPath)) {
      logger.info(`tts: cache hit hash=${textHash.slice(0, 12)} latencyMs=${Date.now() - startedAt}`);
      return { wav: fs.readFileSync(cachedPath), costUsd: 0, cacheHit: true };
    }
    logger.warn(`tts: cached file missing, re-synthesizing hash=${textHash.slice(0, 12)}`);
  }

  // キャラ（音声）は2人からランダム選択（ユーザー設定は廃止）
  const voiceKeys = Object.keys(VOICE_PRESETS) as VoiceKey[];
  const voice = voiceKeys[Math.floor(Math.random() * voiceKeys.length)];

  logger.info(`tts: start voice=${voice} model=${model} textLength=${text.length}`);
  try {
    const { wav, inputTokens, outputTokens } = await synthesizeSpeech(text, voice, model);
    const costUsd = estimateCostUsd(MODEL_PRESETS[model], inputTokens, outputTokens);
    const filename = `${textHash}.wav`;
    fs.writeFileSync(path.join(config.ttsDir, filename), wav);
    upsertTtsAudio({ text, voice, model, textHash, filename, byteSize: wav.length, inputTokens, outputTokens, costUsd });
    logger.info(
      `tts: success voice=${voice} model=${model} tokens=in:${inputTokens}/out:${outputTokens} cost=$${costUsd.toFixed(4)} latencyMs=${Date.now() - startedAt}`
    );
    return { wav, costUsd, cacheHit: false };
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error);
    logger.error(
      `tts: failed voice=${voice} model=${model} latencyMs=${Date.now() - startedAt} error=${errorMessage}`
    );
    throw error;
  }
}

/// クイズ音声のモデルは flash 固定（iOS の AppSettingsKeys.quizTTSModel と一致させること）。
/// キャッシュキーが sha256("model|text") のため、両者がずれるとプリ合成が無駄になる。
export const QUIZ_TTS_MODEL: ModelKey = "flash";

// tts.ts のチャンク合成（並列3）と同程度の控えめな並列度
const PREGEN_CONCURRENCY = 2;

/// クイズ問題生成の成功直後に fire-and-forget で呼ぶ、audioText の一括プリ合成。
/// 1テキストの失敗は他に影響させない（失敗分はセッション開始時の /api/tts で自己修復される）。
export async function pregenerateQuizAudio(questions: QuizQuestion[], word: string): Promise<void> {
  const texts = [
    ...new Set(
      questions
        .map((q) => q.audioText)
        .filter((t): t is string => typeof t === "string" && t.trim().length > 0)
    ),
  ];
  if (texts.length === 0) return;

  const startedAt = Date.now();
  logger.info(`quiz-tts: pregenerate start word="${word}" texts=${texts.length} model=${QUIZ_TTS_MODEL}`);

  let succeeded = 0;
  let failed = 0;
  let totalCostUsd = 0;
  let nextIndex = 0;
  const workers = Array.from({ length: Math.min(PREGEN_CONCURRENCY, texts.length) }, async () => {
    while (nextIndex < texts.length) {
      const text = texts[nextIndex++];
      try {
        const { costUsd } = await getOrSynthesizeTtsAudio(text, QUIZ_TTS_MODEL);
        totalCostUsd += costUsd;
        succeeded++;
      } catch {
        // 失敗ログは getOrSynthesizeTtsAudio 側で出力済み
        failed++;
      }
    }
  });
  await Promise.all(workers);

  logger.info(
    `quiz-tts: pregenerate done word="${word}" succeeded=${succeeded} failed=${failed} ` +
      `cost=$${totalCostUsd.toFixed(4)} latencyMs=${Date.now() - startedAt}`
  );
}
