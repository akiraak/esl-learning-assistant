import "dotenv/config";
import fs from "fs";
import path from "path";
import crypto from "crypto";
import express from "express";
import { config } from "./config";
import { insertRequestLog, insertWordInfoLog } from "./db";
import { adminRouter } from "./admin";
import { ocrAndTranslate } from "./ocrTranslate";
import { generateWordInfo } from "./wordInfo";
import { estimateCostUsd } from "./pricing";
import { logger } from "./logger";
import { synthesizeSpeech, VOICE_PRESETS, MODEL_PRESETS, type VoiceKey, type ModelKey } from "./tts";

process.on("uncaughtException", (error) => {
  logger.error(`uncaughtException: ${error.stack ?? error.message}`);
});
process.on("unhandledRejection", (reason) => {
  logger.error(`unhandledRejection: ${reason instanceof Error ? reason.stack ?? reason.message : String(reason)}`);
});

const app = express();
app.use(express.json({ limit: "20mb" }));

app.use((req, _res, next) => {
  logger.info(`${req.method} ${req.path} from ${req.ip}`);
  next();
});

app.get("/health", (_req, res) => {
  res.json({ status: "ok" });
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

const WORD_MAX_LENGTH = 100;
const WORD_INFO_CONTEXT_MAX_LENGTH = 8000;

app.post("/api/word-info", async (req, res) => {
  const { word, targetLanguage, context, userTranslation } = req.body ?? {};

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
  logger.info(
    `word-info: start word="${trimmedWord}" targetLanguage=${targetLanguage} ` +
      `context=${trimmedContext ? "yes" : "no"} model=${config.wordInfoModel}`
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

    insertWordInfoLog({
      word: trimmedWord,
      targetLanguage,
      userTranslation: trimmedUserTranslation ?? null,
      context: trimmedContext ?? null,
      wordInfoJson: JSON.stringify(result.wordInfo),
      model: result.model,
      inputTokens: result.inputTokens,
      outputTokens: result.outputTokens,
      costUsd,
      status: "success",
      errorMessage: null,
      latencyMs,
    });

    logger.info(`word-info: success word="${trimmedWord}" latencyMs=${latencyMs}`);
    res.json({ wordInfo: result.wordInfo, model: result.model });
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
    });

    logger.error(`word-info: failed word="${trimmedWord}" latencyMs=${latencyMs} error=${errorMessage}`);
    res.status(500).json({ error: errorMessage });
  }
});

const TTS_TEXT_MAX_LENGTH = 2000;

app.post("/api/tts", async (req, res) => {
  const { text, voice, model } = req.body ?? {};

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
  if (voice !== "chobi" && voice !== "naruko") {
    logger.warn(`tts: rejected (invalid voice: ${String(voice)})`);
    res.status(400).json({ error: `voice must be one of: ${Object.keys(VOICE_PRESETS).join(", ")}` });
    return;
  }
  if (model !== "flash" && model !== "pro") {
    logger.warn(`tts: rejected (invalid model: ${String(model)})`);
    res.status(400).json({ error: `model must be one of: ${Object.keys(MODEL_PRESETS).join(", ")}` });
    return;
  }

  const startedAt = Date.now();
  logger.info(`tts: start voice=${voice} model=${model} textLength=${text.length}`);
  try {
    const wav = await synthesizeSpeech(text, voice as VoiceKey, model as ModelKey);
    logger.info(`tts: success voice=${voice} model=${model} latencyMs=${Date.now() - startedAt}`);
    res.set("Content-Type", "audio/wav");
    res.send(wav);
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error);
    logger.error(
      `tts: failed voice=${voice} model=${model} latencyMs=${Date.now() - startedAt} error=${errorMessage}`
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
  logger.info(`ESL Learning Assistant backend listening on http://localhost:${config.port}`);
  logger.info(`Admin dashboard: http://localhost:${config.port}/admin`);
  logger.info(`Log file: ${path.join(config.dataDir, "server.log")}`);
});
