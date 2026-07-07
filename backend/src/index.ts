import "dotenv/config";
import fs from "fs";
import path from "path";
import crypto from "crypto";
import express from "express";
import { config } from "./config";
import {
  countQuizQuestions,
  getStoredNormalization,
  getStoredWord,
  getWordIllustrationByHash,
  insertRequestLog,
  insertTranscriptionLog,
  insertWordInfoLog,
  insertWordNormalizeLog,
  insertWritingFeedbackLog,
  listIllustratedWords,
  listQuizQuestions,
  listStoredWordTexts,
  normalizeWordKey,
  replaceQuizQuestions,
  upsertStoredNormalization,
  upsertStoredWord,
  upsertWordIllustration,
} from "./db";
import { adminRouter } from "./admin";
import { ocrAndTranslate, translateText } from "./ocrTranslate";
import {
  transcribeAudio,
  isSupportedAudioMimeType,
  SUPPORTED_AUDIO_MIME_EXTENSIONS,
} from "./transcribe";
import { generateWordInfo, type WordInfo } from "./wordInfo";
import { normalizeWord } from "./wordNormalize";
import { generateWritingFeedback, type WritingFeedbackRound } from "./writingFeedback";
import { generateQuizQuestions } from "./quizQuestions";
import { estimateCostUsd } from "./pricing";
import { startPricingSync } from "./pricingSync";
import { logger } from "./logger";
import { MODEL_PRESETS, type ModelKey } from "./tts";
import { getOrSynthesizeTtsAudio, pregenerateQuizAudio, regenerateTtsAudio } from "./ttsStore";
import { buildIllustrationPrompt, generateIllustration, ILLUSTRATION_MODEL } from "./illustration";

process.on("uncaughtException", (error) => {
  logger.error(`uncaughtException: ${error.stack ?? error.message}`);
});
process.on("unhandledRejection", (reason) => {
  logger.error(`unhandledRejection: ${reason instanceof Error ? reason.stack ?? reason.message : String(reason)}`);
});

// 公開運用時に意図せず無防備にならないよう fail-fast（ローカル開発でも backend/.env に API_SECRET が必須）
if (!config.apiSecret || config.apiSecret.length < 16 || !/^[A-Za-z0-9_-]+$/.test(config.apiSecret)) {
  logger.error(
    "API_SECRET is required (>=16 chars, [A-Za-z0-9_-] only). aborting to prevent unintended public exposure."
  );
  process.exit(1);
}

function isValidApiSecret(provided: unknown): boolean {
  if (typeof provided !== "string" || !provided) {
    return false;
  }
  // timing-safe 比較（長さ差で漏れないよう sha256 で固定長に揃える）
  const providedHash = crypto.createHash("sha256").update(provided).digest();
  const secretHash = crypto.createHash("sha256").update(config.apiSecret).digest();
  return crypto.timingSafeEqual(providedHash, secretHash);
}

const app = express();
// 音声文字起こしの base64 音声（生 MAX_AUDIO_BYTES=14MB → base64 ~18.7MB）を、ルート側の
// 「audio too large」400 ガードが必ず先に働くだけの余裕を持って受けられるよう 25mb にしている。
// 画像OCRの base64 はこれよりずっと小さい。
app.use(express.json({ limit: "25mb" }));

app.use((req, _res, next) => {
  logger.info(`${req.method} ${req.path} from ${req.ip}`);
  next();
});

// /api/* は X-API-Secret ヘッダ必須。/admin は Cloudflare Access（エッジ側）、/health は無認証のまま
app.use("/api", (req, res, next) => {
  if (!isValidApiSecret(req.header("x-api-secret"))) {
    logger.warn(`api: rejected (invalid X-API-Secret) ${req.method} ${req.originalUrl} from ${req.ip}`);
    res.status(401).json({ error: "unauthorized" });
    return;
  }
  next();
});

app.get("/health", (_req, res) => {
  res.json({ status: "ok" });
});

// クライアントの接続テスト用（/api 配下なので X-API-Secret の一致確認になる）
app.get("/api/ping", (_req, res) => {
  res.json({ ok: true });
});

app.post("/api/ocr-translate", async (req, res) => {
  const { imageBase64, mediaType, targetLanguage } = req.body ?? {};

  if (typeof imageBase64 !== "string" || !imageBase64) {
    logger.warn("ocr-translate: rejected (imageBase64 is required)");
    res.status(400).json({ error: "imageBase64 is required" });
    return;
  }
  if (mediaType !== "image/jpeg" && mediaType !== "image/png") {
    logger.warn(`ocr-translate: rejected (invalid mediaType: ${String(mediaType)})`);
    res.status(400).json({ error: "mediaType must be image/jpeg or image/png" });
    return;
  }
  if (typeof targetLanguage !== "string" || !targetLanguage) {
    logger.warn("ocr-translate: rejected (targetLanguage is required)");
    res.status(400).json({ error: "targetLanguage is required" });
    return;
  }

  const extension = mediaType === "image/jpeg" ? "jpg" : "png";
  const imageFilename = `${Date.now()}-${crypto.randomUUID()}.${extension}`;
  fs.writeFileSync(path.join(config.imagesDir, imageFilename), Buffer.from(imageBase64, "base64"));

  const startedAt = Date.now();
  logger.info(
    `ocr-translate: start image=${imageFilename} targetLanguage=${targetLanguage} ` +
      `ocrModel=${config.ocrModel} translateModel=${config.translateModel}`
  );
  try {
    const result = await ocrAndTranslate(imageBase64, mediaType, targetLanguage);
    const latencyMs = Date.now() - startedAt;
    const ocrCostUsd = estimateCostUsd(result.ocrModel, result.ocrInputTokens, result.ocrOutputTokens);
    const translateCostUsd = estimateCostUsd(
      result.translateModel,
      result.translateInputTokens,
      result.translateOutputTokens
    );

    insertRequestLog({
      imageFilename,
      targetLanguage,
      ocrText: result.ocrText,
      translatedText: result.translatedText,
      ocrModel: result.ocrModel,
      ocrInputTokens: result.ocrInputTokens,
      ocrOutputTokens: result.ocrOutputTokens,
      translateModel: result.translateModel,
      translateInputTokens: result.translateInputTokens,
      translateOutputTokens: result.translateOutputTokens,
      ocrCostUsd,
      translateCostUsd,
      costUsd: ocrCostUsd + translateCostUsd,
      status: "success",
      errorMessage: null,
      latencyMs,
    });

    logger.info(`ocr-translate: success image=${imageFilename} latencyMs=${latencyMs}`);
    res.json({
      ocrText: result.ocrText,
      translatedText: result.translatedText,
      translationLanguage: targetLanguage,
    });
  } catch (error) {
    const latencyMs = Date.now() - startedAt;
    const errorMessage = error instanceof Error ? error.message : String(error);

    insertRequestLog({
      imageFilename,
      targetLanguage,
      ocrText: null,
      translatedText: null,
      ocrModel: config.ocrModel,
      ocrInputTokens: 0,
      ocrOutputTokens: 0,
      translateModel: null,
      translateInputTokens: 0,
      translateOutputTokens: 0,
      ocrCostUsd: 0,
      translateCostUsd: 0,
      costUsd: 0,
      status: "error",
      errorMessage,
      latencyMs,
    });

    logger.error(`ocr-translate: failed image=${imageFilename} latencyMs=${latencyMs} error=${errorMessage}`);
    res.status(500).json({ error: errorMessage });
  }
});

// 音声インライン送信の上限（生バイト）。base64 は約1.33倍に膨らむため 14MB でも
// JSON ボディは ~18.7MB で express.json の 25mb 上限に収まり、この 400 ガードが 413 より先に働く。
// Gemini のインライン上限（~20MB/リクエスト）にも収まる。超過分は「短いクリップに分割」を促す
// （長尺は将来 File API 対応）。iOS 側も送信前に同じ上限でチェックする（Phase 3）。
const MAX_AUDIO_BYTES = 14 * 1024 * 1024;

// 音声（base64）→ Gemini で英文文字起こし → 既存 translateText で英→目的言語。
// 写真OCR（/api/ocr-translate）と同型: サーバキャッシュは持たず結果は iOS 側 AudioClip に保存、
// ここでは料金・履歴を transcription_requests に記録する（管理画面表示は Phase 5）。
app.post("/api/transcribe-translate", async (req, res) => {
  const { audioBase64, mediaType, targetLanguage } = req.body ?? {};

  if (typeof audioBase64 !== "string" || !audioBase64) {
    logger.warn("transcribe-translate: rejected (audioBase64 is required)");
    res.status(400).json({ error: "audioBase64 is required" });
    return;
  }
  if (!isSupportedAudioMimeType(mediaType)) {
    logger.warn(`transcribe-translate: rejected (unsupported mediaType: ${String(mediaType)})`);
    res.status(400).json({
      error: `mediaType must be one of: ${Object.keys(SUPPORTED_AUDIO_MIME_EXTENSIONS).join(", ")}`,
    });
    return;
  }
  if (typeof targetLanguage !== "string" || !targetLanguage) {
    logger.warn("transcribe-translate: rejected (targetLanguage is required)");
    res.status(400).json({ error: "targetLanguage is required" });
    return;
  }

  const audioBuffer = Buffer.from(audioBase64, "base64");
  if (audioBuffer.length === 0) {
    logger.warn("transcribe-translate: rejected (audioBase64 decoded to 0 bytes)");
    res.status(400).json({ error: "audioBase64 is not valid base64 audio" });
    return;
  }
  if (audioBuffer.length > MAX_AUDIO_BYTES) {
    logger.warn(`transcribe-translate: rejected (audio too large: ${audioBuffer.length} bytes)`);
    res.status(400).json({
      error: `audio too large (${(audioBuffer.length / 1024 / 1024).toFixed(1)}MB, max ${MAX_AUDIO_BYTES / 1024 / 1024}MB). split into shorter clips`,
    });
    return;
  }

  const extension = SUPPORTED_AUDIO_MIME_EXTENSIONS[mediaType];
  const audioFilename = `${Date.now()}-${crypto.randomUUID()}.${extension}`;
  fs.writeFileSync(path.join(config.audioDir, audioFilename), audioBuffer);

  const startedAt = Date.now();
  logger.info(
    `transcribe-translate: start audio=${audioFilename} bytes=${audioBuffer.length} ` +
      `mediaType=${mediaType} targetLanguage=${targetLanguage} ` +
      `transcriptionModel=${config.transcriptionModel} translateModel=${config.translateModel}`
  );
  try {
    const transcription = await transcribeAudio(audioBase64, mediaType);
    const translation = await translateText(transcription.englishText, targetLanguage);
    const latencyMs = Date.now() - startedAt;

    const transcriptionCostUsd = estimateCostUsd(
      config.transcriptionModel,
      transcription.inputTokens,
      transcription.outputTokens
    );
    const translateCostUsd = estimateCostUsd(
      config.translateModel,
      translation.inputTokens,
      translation.outputTokens
    );

    insertTranscriptionLog({
      audioFilename,
      mediaType,
      targetLanguage,
      byteSize: audioBuffer.length,
      englishText: transcription.englishText,
      translatedText: translation.text,
      transcriptionModel: config.transcriptionModel,
      transcriptionInputTokens: transcription.inputTokens,
      transcriptionOutputTokens: transcription.outputTokens,
      translateModel: config.translateModel,
      translateInputTokens: translation.inputTokens,
      translateOutputTokens: translation.outputTokens,
      transcriptionCostUsd,
      translateCostUsd,
      costUsd: transcriptionCostUsd + translateCostUsd,
      status: "success",
      errorMessage: null,
      latencyMs,
    });

    logger.info(
      `transcribe-translate: success audio=${audioFilename} latencyMs=${latencyMs} ` +
        `tokens=transcribe:${transcription.inputTokens}/${transcription.outputTokens} ` +
        `translate:${translation.inputTokens}/${translation.outputTokens} ` +
        `cost=$${(transcriptionCostUsd + translateCostUsd).toFixed(4)}`
    );
    res.json({
      englishText: transcription.englishText,
      translatedText: translation.text,
      translationLanguage: targetLanguage,
    });
  } catch (error) {
    const latencyMs = Date.now() - startedAt;
    const errorMessage = error instanceof Error ? error.message : String(error);

    insertTranscriptionLog({
      audioFilename,
      mediaType,
      targetLanguage,
      byteSize: audioBuffer.length,
      englishText: null,
      translatedText: null,
      transcriptionModel: config.transcriptionModel,
      transcriptionInputTokens: 0,
      transcriptionOutputTokens: 0,
      translateModel: null,
      translateInputTokens: 0,
      translateOutputTokens: 0,
      transcriptionCostUsd: 0,
      translateCostUsd: 0,
      costUsd: 0,
      status: "error",
      errorMessage,
      latencyMs,
    });

    logger.error(`transcribe-translate: failed audio=${audioFilename} latencyMs=${latencyMs} error=${errorMessage}`);
    res.status(500).json({ error: errorMessage });
  }
});

const WORD_MAX_LENGTH = 100;
const WORD_INFO_CONTEXT_MAX_LENGTH = 8000;

app.post("/api/word-info", async (req, res) => {
  const { word, targetLanguage, context, userTranslation, regenerate } = req.body ?? {};

  if (typeof word !== "string" || !word.trim()) {
    logger.warn("word-info: rejected (word is required)");
    res.status(400).json({ error: "word is required" });
    return;
  }
  if (word.length > WORD_MAX_LENGTH) {
    logger.warn(`word-info: rejected (word too long: ${word.length})`);
    res.status(400).json({ error: `word must be ${WORD_MAX_LENGTH} characters or fewer` });
    return;
  }
  if (typeof targetLanguage !== "string" || !targetLanguage) {
    logger.warn("word-info: rejected (targetLanguage is required)");
    res.status(400).json({ error: "targetLanguage is required" });
    return;
  }
  if (context !== undefined && typeof context !== "string") {
    logger.warn("word-info: rejected (context must be a string)");
    res.status(400).json({ error: "context must be a string" });
    return;
  }
  if (userTranslation !== undefined && typeof userTranslation !== "string") {
    logger.warn("word-info: rejected (userTranslation must be a string)");
    res.status(400).json({ error: "userTranslation must be a string" });
    return;
  }
  if (regenerate !== undefined && typeof regenerate !== "boolean") {
    logger.warn("word-info: rejected (regenerate must be a boolean)");
    res.status(400).json({ error: "regenerate must be a boolean" });
    return;
  }

  const trimmedWord = word.trim();
  // 教科書ページ全文が来るため長すぎる場合は先頭側を残して切り詰める（拒否はしない）
  const trimmedContext =
    typeof context === "string" && context.trim()
      ? context.trim().slice(0, WORD_INFO_CONTEXT_MAX_LENGTH)
      : undefined;
  const trimmedUserTranslation =
    typeof userTranslation === "string" && userTranslation.trim()
      ? userTranslation.trim()
      : undefined;

  const startedAt = Date.now();

  // 保存済みなら Claude API を呼ばずに返す（regenerate 指定時は作りなおす）
  if (!regenerate) {
    const stored = getStoredWord(trimmedWord, targetLanguage);
    if (stored) {
      const latencyMs = Date.now() - startedAt;
      insertWordInfoLog({
        word: trimmedWord,
        targetLanguage,
        userTranslation: trimmedUserTranslation ?? null,
        context: trimmedContext ?? null,
        wordInfoJson: stored.word_info_json,
        model: stored.model,
        inputTokens: 0,
        outputTokens: 0,
        costUsd: 0,
        status: "success",
        errorMessage: null,
        latencyMs,
        cacheHit: true,
      });
      logger.info(`word-info: cache hit word="${trimmedWord}" latencyMs=${latencyMs}`);
      res.json({ wordInfo: JSON.parse(stored.word_info_json), model: stored.model, cached: true });
      return;
    }
  }

  logger.info(
    `word-info: start word="${trimmedWord}" targetLanguage=${targetLanguage} ` +
      `context=${trimmedContext ? "yes" : "no"} regenerate=${regenerate === true} model=${config.wordInfoModel}`
  );
  try {
    const result = await generateWordInfo(
      trimmedWord,
      targetLanguage,
      trimmedContext,
      trimmedUserTranslation
    );
    const latencyMs = Date.now() - startedAt;
    const costUsd = estimateCostUsd(result.model, result.inputTokens, result.outputTokens);
    const wordInfoJson = JSON.stringify(result.wordInfo);

    upsertStoredWord({
      word: trimmedWord,
      targetLanguage,
      wordInfoJson,
      model: result.model,
      context: trimmedContext ?? null,
      userTranslation: trimmedUserTranslation ?? null,
    });

    insertWordInfoLog({
      word: trimmedWord,
      targetLanguage,
      userTranslation: trimmedUserTranslation ?? null,
      context: trimmedContext ?? null,
      wordInfoJson,
      model: result.model,
      inputTokens: result.inputTokens,
      outputTokens: result.outputTokens,
      costUsd,
      status: "success",
      errorMessage: null,
      latencyMs,
      cacheHit: false,
    });

    logger.info(`word-info: success word="${trimmedWord}" latencyMs=${latencyMs}`);
    res.json({ wordInfo: result.wordInfo, model: result.model, cached: false });
  } catch (error) {
    const latencyMs = Date.now() - startedAt;
    const errorMessage = error instanceof Error ? error.message : String(error);

    insertWordInfoLog({
      word: trimmedWord,
      targetLanguage,
      userTranslation: trimmedUserTranslation ?? null,
      context: trimmedContext ?? null,
      wordInfoJson: null,
      model: config.wordInfoModel,
      inputTokens: 0,
      outputTokens: 0,
      costUsd: 0,
      status: "error",
      errorMessage,
      latencyMs,
      cacheHit: false,
    });

    logger.error(`word-info: failed word="${trimmedWord}" latencyMs=${latencyMs} error=${errorMessage}`);
    res.status(500).json({ error: errorMessage });
  }
});

// 入力語を辞書見出し語（lemma）へ正規化する（原形化・綴り訂正）。登録・派生生成の前段で呼び、
// 誤った語での連鎖生成を防ぐ。結果は (input, targetLanguage) 単位でキャッシュする。
// docs/plans/word-input-normalization.md 参照。
app.post("/api/word-normalize", async (req, res) => {
  const { word, targetLanguage, regenerate } = req.body ?? {};

  if (typeof word !== "string" || !word.trim()) {
    logger.warn("word-normalize: rejected (word is required)");
    res.status(400).json({ error: "word is required" });
    return;
  }
  if (word.length > WORD_MAX_LENGTH) {
    logger.warn(`word-normalize: rejected (word too long: ${word.length})`);
    res.status(400).json({ error: `word must be ${WORD_MAX_LENGTH} characters or fewer` });
    return;
  }
  if (typeof targetLanguage !== "string" || !targetLanguage) {
    logger.warn("word-normalize: rejected (targetLanguage is required)");
    res.status(400).json({ error: "targetLanguage is required" });
    return;
  }
  if (regenerate !== undefined && typeof regenerate !== "boolean") {
    logger.warn("word-normalize: rejected (regenerate must be a boolean)");
    res.status(400).json({ error: "regenerate must be a boolean" });
    return;
  }

  const trimmedWord = word.trim();
  const startedAt = Date.now();

  // 保存済みなら Claude API を呼ばずに返す（regenerate 指定時は作りなおす）
  if (!regenerate) {
    const stored = getStoredNormalization(trimmedWord, targetLanguage);
    if (stored) {
      const latencyMs = Date.now() - startedAt;
      insertWordNormalizeLog({
        input: trimmedWord,
        targetLanguage,
        lemma: stored.lemma,
        resultStatus: stored.status,
        reason: stored.reason,
        model: stored.model,
        inputTokens: 0,
        outputTokens: 0,
        costUsd: 0,
        status: "success",
        errorMessage: null,
        latencyMs,
        cacheHit: true,
      });
      logger.info(`word-normalize: cache hit word="${trimmedWord}" status=${stored.status} latencyMs=${latencyMs}`);
      res.json({
        input: trimmedWord,
        lemma: stored.lemma,
        status: stored.status,
        reason: stored.reason ?? "",
        cached: true,
      });
      return;
    }
  }

  logger.info(
    `word-normalize: start word="${trimmedWord}" targetLanguage=${targetLanguage} ` +
      `regenerate=${regenerate === true} model=${config.wordNormalizeModel}`
  );
  try {
    const result = await normalizeWord(trimmedWord, targetLanguage);
    const latencyMs = Date.now() - startedAt;
    const costUsd = estimateCostUsd(result.model, result.inputTokens, result.outputTokens);
    const { status, lemma, reason } = result.normalization;

    upsertStoredNormalization({
      input: trimmedWord,
      targetLanguage,
      lemma,
      status,
      reason: reason || null,
      model: result.model,
    });

    insertWordNormalizeLog({
      input: trimmedWord,
      targetLanguage,
      lemma,
      resultStatus: status,
      reason: reason || null,
      model: result.model,
      inputTokens: result.inputTokens,
      outputTokens: result.outputTokens,
      costUsd,
      status: "success",
      errorMessage: null,
      latencyMs,
      cacheHit: false,
    });

    logger.info(`word-normalize: success word="${trimmedWord}" status=${status} lemma="${lemma}" latencyMs=${latencyMs}`);
    res.json({ input: trimmedWord, lemma, status, reason, cached: false });
  } catch (error) {
    const latencyMs = Date.now() - startedAt;
    const errorMessage = error instanceof Error ? error.message : String(error);

    insertWordNormalizeLog({
      input: trimmedWord,
      targetLanguage,
      lemma: null,
      resultStatus: null,
      reason: null,
      model: config.wordNormalizeModel,
      inputTokens: 0,
      outputTokens: 0,
      costUsd: 0,
      status: "error",
      errorMessage,
      latencyMs,
      cacheHit: false,
    });

    logger.error(`word-normalize: failed word="${trimmedWord}" latencyMs=${latencyMs} error=${errorMessage}`);
    res.status(500).json({ error: errorMessage });
  }
});

const WRITING_TEXT_MAX_LENGTH = 5000;
const DEFAULT_EXPLANATION_LANGUAGE = "ja";
// 反復改善の履歴として AI に渡す過去ラウンドの上限（トークン肥大を防ぐため直近のみ）
const WRITING_HISTORY_MAX_ROUNDS = 20;

/// リクエストの history を防御的に正規化する。配列でなければ [] を返し、各ラウンドの文字列フィールドを
/// クランプ、直近 WRITING_HISTORY_MAX_ROUNDS 件に丸める。無効な要素は落とす。
function sanitizeWritingHistory(raw: unknown): WritingFeedbackRound[] {
  if (!Array.isArray(raw)) return [];
  const clamp = (value: unknown): string =>
    typeof value === "string" ? value.slice(0, WRITING_TEXT_MAX_LENGTH) : "";
  return raw
    .filter((item): item is Record<string, unknown> => typeof item === "object" && item !== null)
    .map((item) => ({
      englishText: clamp(item.englishText),
      japaneseText: clamp(item.japaneseText),
      correctedText: clamp(item.correctedText),
      explanation: clamp(item.explanation),
    }))
    .filter((round) => round.englishText.trim() !== "" && round.correctedText.trim() !== "")
    .slice(-WRITING_HISTORY_MAX_ROUNDS);
}

// 作文添削。英文と「伝えたかった意図（母語）」を渡し、修正英文＋母語解説を返す。
// 作文本文は毎回異なりキャッシュが効かないため、サーバ側は保存せずログ用途のみ。
app.post("/api/writing-feedback", async (req, res) => {
  const { englishText, japaneseText, explanationLanguage, history } = req.body ?? {};

  if (typeof englishText !== "string" || !englishText.trim()) {
    logger.warn("writing-feedback: rejected (englishText is required)");
    res.status(400).json({ error: "englishText is required" });
    return;
  }
  if (englishText.length > WRITING_TEXT_MAX_LENGTH) {
    logger.warn(`writing-feedback: rejected (englishText too long: ${englishText.length})`);
    res.status(400).json({ error: `englishText must be ${WRITING_TEXT_MAX_LENGTH} characters or fewer` });
    return;
  }
  if (typeof japaneseText !== "string" || !japaneseText.trim()) {
    logger.warn("writing-feedback: rejected (japaneseText is required)");
    res.status(400).json({ error: "japaneseText is required" });
    return;
  }
  if (japaneseText.length > WRITING_TEXT_MAX_LENGTH) {
    logger.warn(`writing-feedback: rejected (japaneseText too long: ${japaneseText.length})`);
    res.status(400).json({ error: `japaneseText must be ${WRITING_TEXT_MAX_LENGTH} characters or fewer` });
    return;
  }
  if (explanationLanguage !== undefined && typeof explanationLanguage !== "string") {
    logger.warn("writing-feedback: rejected (explanationLanguage must be a string)");
    res.status(400).json({ error: "explanationLanguage must be a string" });
    return;
  }

  const trimmedEnglish = englishText.trim();
  const trimmedJapanese = japaneseText.trim();
  const resolvedLanguage =
    typeof explanationLanguage === "string" && explanationLanguage.trim()
      ? explanationLanguage.trim()
      : DEFAULT_EXPLANATION_LANGUAGE;

  const sanitizedHistory = sanitizeWritingHistory(history);

  const startedAt = Date.now();
  logger.info(
    `writing-feedback: start englishLen=${trimmedEnglish.length} japaneseLen=${trimmedJapanese.length} ` +
      `historyRounds=${sanitizedHistory.length} explanationLanguage=${resolvedLanguage} model=${config.writingFeedbackModel}`
  );

  try {
    const result = await generateWritingFeedback(
      trimmedEnglish,
      trimmedJapanese,
      resolvedLanguage,
      sanitizedHistory
    );
    const latencyMs = Date.now() - startedAt;
    const costUsd = estimateCostUsd(result.model, result.inputTokens, result.outputTokens);
    const feedbackJson = JSON.stringify(result.feedback);

    insertWritingFeedbackLog({
      englishText: trimmedEnglish,
      japaneseText: trimmedJapanese,
      explanationLanguage: resolvedLanguage,
      feedbackJson,
      model: result.model,
      inputTokens: result.inputTokens,
      outputTokens: result.outputTokens,
      costUsd,
      status: "success",
      errorMessage: null,
      latencyMs,
    });

    logger.info(`writing-feedback: success latencyMs=${latencyMs}`);
    res.json({ feedback: result.feedback, model: result.model });
  } catch (error) {
    const latencyMs = Date.now() - startedAt;
    const errorMessage = error instanceof Error ? error.message : String(error);

    insertWritingFeedbackLog({
      englishText: trimmedEnglish,
      japaneseText: trimmedJapanese,
      explanationLanguage: resolvedLanguage,
      feedbackJson: null,
      model: config.writingFeedbackModel,
      inputTokens: 0,
      outputTokens: 0,
      costUsd: 0,
      status: "error",
      errorMessage,
      latencyMs,
    });

    logger.error(`writing-feedback: failed latencyMs=${latencyMs} error=${errorMessage}`);
    res.status(500).json({ error: errorMessage });
  }
});

// 復習クイズ問題の生成（docs/plans/archive/quiz-questions-server-storage.md）。
// 単語情報（words テーブル）を素材に、1単語分の問題（形式×バリエーション）を生成して保存する。
// iOS は単語情報の生成成功後にこれを fire-and-forget で呼ぶ。
app.post("/api/quiz-questions/generate", async (req, res) => {
  const { word, targetLanguage, regenerate } = req.body ?? {};

  if (typeof word !== "string" || !word.trim()) {
    logger.warn("quiz-questions: rejected (word is required)");
    res.status(400).json({ error: "word is required" });
    return;
  }
  if (word.length > WORD_MAX_LENGTH) {
    logger.warn(`quiz-questions: rejected (word too long: ${word.length})`);
    res.status(400).json({ error: `word must be ${WORD_MAX_LENGTH} characters or fewer` });
    return;
  }
  if (typeof targetLanguage !== "string" || !targetLanguage) {
    logger.warn("quiz-questions: rejected (targetLanguage is required)");
    res.status(400).json({ error: "targetLanguage is required" });
    return;
  }
  if (regenerate !== undefined && typeof regenerate !== "boolean") {
    logger.warn("quiz-questions: rejected (regenerate must be a boolean)");
    res.status(400).json({ error: "regenerate must be a boolean" });
    return;
  }

  const trimmedWord = word.trim();
  const startedAt = Date.now();

  // 生成済みなら Claude API を呼ばずに返す（regenerate 指定時は作りなおす）
  if (!regenerate) {
    const count = countQuizQuestions(trimmedWord, targetLanguage);
    if (count > 0) {
      logger.info(`quiz-questions: cache hit word="${trimmedWord}" count=${count}`);
      res.json({ cached: true, count });
      return;
    }
  }

  // 素材は保存済みの単語情報。無ければ先に /api/word-info を呼ぶ必要がある
  const stored = getStoredWord(trimmedWord, targetLanguage);
  if (!stored) {
    logger.warn(`quiz-questions: rejected (word info not found for "${trimmedWord}")`);
    res.status(404).json({ error: "word info not found. generate word info first" });
    return;
  }

  logger.info(
    `quiz-questions: start word="${trimmedWord}" targetLanguage=${targetLanguage} ` +
      `regenerate=${regenerate === true} model=${config.quizQuestionModel}`
  );
  try {
    const wordInfo = JSON.parse(stored.word_info_json) as WordInfo;
    const result = await generateQuizQuestions(
      trimmedWord,
      wordInfo,
      listIllustratedWords(targetLanguage),
      listStoredWordTexts(targetLanguage)
    );
    const latencyMs = Date.now() - startedAt;

    if (result.questions.length === 0) {
      const errorMessage = result.errors.join(" / ") || "no questions generated";
      logger.error(`quiz-questions: failed word="${trimmedWord}" latencyMs=${latencyMs} error=${errorMessage}`);
      res.status(500).json({ error: errorMessage });
      return;
    }

    replaceQuizQuestions(
      trimmedWord,
      targetLanguage,
      result.questions.map((generated) => ({
        word: trimmedWord,
        targetLanguage,
        format: generated.question.format,
        variantIndex: generated.variantIndex,
        questionJson: JSON.stringify(generated.question),
        model: generated.model,
        inputTokens: generated.inputTokens,
        outputTokens: generated.outputTokens,
        costUsd:
          generated.model === "rule"
            ? 0
            : estimateCostUsd(generated.model, generated.inputTokens, generated.outputTokens),
      }))
    );

    // 音声出題用の audioText をサーバ側で AI 生成しておく（レスポンスはブロックしない）。
    // 失敗分はセッション開始時の /api/tts キャッシュミス合成で自己修復される。
    void pregenerateQuizAudio(
      result.questions.map((generated) => generated.question),
      trimmedWord
    );

    const totalCostUsd = estimateCostUsd(
      config.quizQuestionModel,
      result.totalInputTokens,
      result.totalOutputTokens
    );
    logger.info(
      `quiz-questions: success word="${trimmedWord}" count=${result.questions.length} ` +
        `partialErrors=${result.errors.length} latencyMs=${latencyMs} ` +
        `tokens=${result.totalInputTokens}/${result.totalOutputTokens} costUsd=${totalCostUsd.toFixed(4)}`
    );
    if (result.errors.length > 0) {
      logger.warn(`quiz-questions: partial failure word="${trimmedWord}" errors=${result.errors.join(" / ")}`);
    }
    res.json({ cached: false, count: result.questions.length, partialErrors: result.errors });
  } catch (error) {
    const latencyMs = Date.now() - startedAt;
    const errorMessage = error instanceof Error ? error.message : String(error);
    logger.error(`quiz-questions: failed word="${trimmedWord}" latencyMs=${latencyMs} error=${errorMessage}`);
    res.status(500).json({ error: errorMessage });
  }
});

// 保存済み問題のバッチ取得。復習セッション開始時に due 単語（最大20語）分をまとめて返す。
const QUIZ_QUERY_MAX_WORDS = 50;

app.post("/api/quiz-questions/query", (req, res) => {
  const { words, targetLanguage } = req.body ?? {};

  if (!Array.isArray(words) || words.length === 0 || words.some((w) => typeof w !== "string" || !w.trim())) {
    logger.warn("quiz-questions/query: rejected (words must be a non-empty string array)");
    res.status(400).json({ error: "words must be a non-empty string array" });
    return;
  }
  if (words.length > QUIZ_QUERY_MAX_WORDS) {
    logger.warn(`quiz-questions/query: rejected (too many words: ${words.length})`);
    res.status(400).json({ error: `words must be ${QUIZ_QUERY_MAX_WORDS} or fewer` });
    return;
  }
  if (typeof targetLanguage !== "string" || !targetLanguage) {
    logger.warn("quiz-questions/query: rejected (targetLanguage is required)");
    res.status(400).json({ error: "targetLanguage is required" });
    return;
  }

  // キーは正規化済み単語（iOS 側も同じ正規化で引く）
  const questions: Record<string, unknown[]> = {};
  for (const word of words as string[]) {
    const rows = listQuizQuestions(word, targetLanguage);
    if (rows.length > 0) {
      questions[normalizeWordKey(word)] = rows.map((row) => JSON.parse(row.question_json));
    }
  }
  logger.info(
    `quiz-questions/query: words=${words.length} hit=${Object.keys(questions).length} targetLanguage=${targetLanguage}`
  );
  res.json({ questions });
});

// 長文はtts.ts側で文単位のチャンクに分割して合成するため、上限は課金・所要時間の歯止めとしての値
const TTS_TEXT_MAX_LENGTH = 20000;

app.post("/api/tts", async (req, res) => {
  const { text, model, regenerate } = req.body ?? {};

  if (typeof text !== "string" || !text.trim()) {
    logger.warn("tts: rejected (text is required)");
    res.status(400).json({ error: "text is required" });
    return;
  }
  if (text.length > TTS_TEXT_MAX_LENGTH) {
    logger.warn(`tts: rejected (text too long: ${text.length})`);
    res.status(400).json({ error: `text must be ${TTS_TEXT_MAX_LENGTH} characters or fewer` });
    return;
  }
  if (model !== "flash" && model !== "pro") {
    logger.warn(`tts: rejected (invalid model: ${String(model)})`);
    res.status(400).json({ error: `model must be one of: ${Object.keys(MODEL_PRESETS).join(", ")}` });
    return;
  }

  // キャッシュ検索→合成→保存の実体は ttsStore.ts（ログもそちらで出力する）。
  // regenerate=true のときはサーバキャッシュを破棄してから合成し直す（クライアントの「作り直す」用。
  // ボイスも再抽選される）。単なる再取得ではなく本当に音声を作り直したい場合に使う。
  try {
    const { wav } =
      regenerate === true
        ? await regenerateTtsAudio(text, model as ModelKey)
        : await getOrSynthesizeTtsAudio(text, model as ModelKey);
    res.set("Content-Type", "audio/wav");
    res.send(wav);
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error);
    res.status(500).json({ error: errorMessage });
  }
});

// 自動生成は第1義（senseIndex=0）のみ。将来「意味ごとに生成」に拡張できるよう senseIndex を受け付ける
const ILLUSTRATION_SENSE_INDEX_MAX = 9;

app.post("/api/word-illustration", async (req, res) => {
  const { word, targetLanguage, senseIndex } = req.body ?? {};

  if (typeof word !== "string" || !word.trim()) {
    logger.warn("word-illustration: rejected (word is required)");
    res.status(400).json({ error: "word is required" });
    return;
  }
  if (word.length > WORD_MAX_LENGTH) {
    logger.warn(`word-illustration: rejected (word too long: ${word.length})`);
    res.status(400).json({ error: `word must be ${WORD_MAX_LENGTH} characters or fewer` });
    return;
  }
  if (typeof targetLanguage !== "string" || !targetLanguage) {
    logger.warn("word-illustration: rejected (targetLanguage is required)");
    res.status(400).json({ error: "targetLanguage is required" });
    return;
  }
  if (
    senseIndex !== undefined &&
    (typeof senseIndex !== "number" || !Number.isInteger(senseIndex) || senseIndex < 0 || senseIndex > ILLUSTRATION_SENSE_INDEX_MAX)
  ) {
    logger.warn(`word-illustration: rejected (invalid senseIndex: ${String(senseIndex)})`);
    res.status(400).json({ error: `senseIndex must be an integer between 0 and ${ILLUSTRATION_SENSE_INDEX_MAX}` });
    return;
  }

  const trimmedWord = word.trim();
  const resolvedSenseIndex = senseIndex ?? 0;
  const startedAt = Date.now();

  // 同一 (model, word, targetLanguage, senseIndex) は保存済みPNGを返す（OpenAI再呼び出しなし）。
  // ファイルが欠損していた場合は再生成して自己修復する。
  const keyHash = crypto
    .createHash("sha256")
    .update(`${ILLUSTRATION_MODEL}|${normalizeWordKey(trimmedWord)}|${targetLanguage}|${resolvedSenseIndex}`)
    .digest("hex");
  const cached = getWordIllustrationByHash(keyHash);
  if (cached) {
    const cachedPath = path.join(config.illustrationsDir, cached.filename);
    if (fs.existsSync(cachedPath)) {
      logger.info(`word-illustration: cache hit hash=${keyHash.slice(0, 12)} latencyMs=${Date.now() - startedAt}`);
      res.set("Content-Type", "image/png");
      res.send(fs.readFileSync(cachedPath));
      return;
    }
    logger.warn(`word-illustration: cached file missing, re-generating hash=${keyHash.slice(0, 12)}`);
  }

  // 保存済みの単語情報（words.word_info_json）から該当義の英語定義と例文を取ってプロンプトに含める。
  // 未生成の単語や該当義が無い場合は単語のみで生成する。
  let definition: string | undefined;
  let exampleSentence: string | undefined;
  const stored = getStoredWord(trimmedWord, targetLanguage);
  if (stored) {
    try {
      const info = JSON.parse(stored.word_info_json) as WordInfo;
      definition = info.senses[resolvedSenseIndex]?.englishDefinition || undefined;
      exampleSentence = info.examples[0]?.english || undefined;
    } catch {
      logger.warn(`word-illustration: broken word_info_json for word="${trimmedWord}", generating without it`);
    }
  }

  const prompt = buildIllustrationPrompt(trimmedWord, definition, exampleSentence);
  logger.info(
    `word-illustration: start word="${trimmedWord}" targetLanguage=${targetLanguage} ` +
      `senseIndex=${resolvedSenseIndex} wordInfo=${stored ? "yes" : "no"} model=${ILLUSTRATION_MODEL}`
  );
  try {
    const { png, inputTokens, outputTokens } = await generateIllustration(prompt);
    const costUsd = estimateCostUsd(ILLUSTRATION_MODEL, inputTokens, outputTokens);
    const filename = `${keyHash}.png`;
    fs.writeFileSync(path.join(config.illustrationsDir, filename), png);
    upsertWordIllustration({
      word: normalizeWordKey(trimmedWord),
      targetLanguage,
      senseIndex: resolvedSenseIndex,
      prompt,
      model: ILLUSTRATION_MODEL,
      keyHash,
      filename,
      byteSize: png.length,
      inputTokens,
      outputTokens,
      costUsd,
    });
    logger.info(
      `word-illustration: success word="${trimmedWord}" tokens=in:${inputTokens}/out:${outputTokens} ` +
        `cost=$${costUsd.toFixed(4)} latencyMs=${Date.now() - startedAt}`
    );
    res.set("Content-Type", "image/png");
    res.send(png);
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error);
    logger.error(
      `word-illustration: failed word="${trimmedWord}" latencyMs=${Date.now() - startedAt} error=${errorMessage}`
    );
    res.status(500).json({ error: errorMessage });
  }
});

app.use("/admin", adminRouter);

app.listen(config.port, () => {
  if (!config.anthropicApiKey) {
    logger.warn("ANTHROPIC_API_KEY is not set. /api/ocr-translate will fail.");
  }
  if (!config.geminiApiKey) {
    logger.warn("GEMINI_API_KEY is not set. /api/tts will fail.");
  }
  if (!config.openaiApiKey) {
    logger.warn("OPENAI_API_KEY is not set. /api/word-illustration will fail.");
  }
  logger.info(`ESL Assistant backend listening on http://localhost:${config.port}`);
  logger.info(`Admin dashboard: http://localhost:${config.port}/admin`);
  logger.info(`Log file: ${path.join(config.dataDir, "server.log")}`);
  startPricingSync();
});
