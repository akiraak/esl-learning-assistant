import "dotenv/config";
import fs from "fs";
import path from "path";
import crypto from "crypto";
import express from "express";
import { config } from "./config";
import {
  countQuizQuestions,
  getStoredWord,
  getTtsAudioByHash,
  getWordIllustrationByHash,
  insertRequestLog,
  insertWordInfoLog,
  listIllustratedWords,
  listQuizQuestions,
  listStoredWordTexts,
  normalizeWordKey,
  replaceQuizQuestions,
  upsertStoredWord,
  upsertTtsAudio,
  upsertWordIllustration,
} from "./db";
import { adminRouter } from "./admin";
import { ocrAndTranslate } from "./ocrTranslate";
import { generateWordInfo, type WordInfo } from "./wordInfo";
import { generateQuizQuestions } from "./quizQuestions";
import { estimateCostUsd } from "./pricing";
import { startPricingSync } from "./pricingSync";
import { logger } from "./logger";
import { synthesizeSpeech, VOICE_PRESETS, MODEL_PRESETS, type VoiceKey, type ModelKey } from "./tts";
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
app.use(express.json({ limit: "20mb" }));

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

// 復習クイズ問題の生成（docs/plans/quiz-questions-server-storage.md）。
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

  // 同一 (voice, model, text) は保存済みWAVを返す（Gemini再呼び出しなし）。
  // ファイルが欠損していた場合は再合成して自己修復する。
  const textHash = crypto.createHash("sha256").update(`${voice}|${model}|${text}`).digest("hex");
  const cached = getTtsAudioByHash(textHash);
  if (cached) {
    const cachedPath = path.join(config.ttsDir, cached.filename);
    if (fs.existsSync(cachedPath)) {
      logger.info(`tts: cache hit hash=${textHash.slice(0, 12)} latencyMs=${Date.now() - startedAt}`);
      res.set("Content-Type", "audio/wav");
      res.send(fs.readFileSync(cachedPath));
      return;
    }
    logger.warn(`tts: cached file missing, re-synthesizing hash=${textHash.slice(0, 12)}`);
  }

  logger.info(`tts: start voice=${voice} model=${model} textLength=${text.length}`);
  try {
    const { wav, inputTokens, outputTokens } = await synthesizeSpeech(text, voice as VoiceKey, model as ModelKey);
    const costUsd = estimateCostUsd(MODEL_PRESETS[model as ModelKey], inputTokens, outputTokens);
    const filename = `${textHash}.wav`;
    fs.writeFileSync(path.join(config.ttsDir, filename), wav);
    upsertTtsAudio({ text, voice, model, textHash, filename, byteSize: wav.length, inputTokens, outputTokens, costUsd });
    logger.info(
      `tts: success voice=${voice} model=${model} tokens=in:${inputTokens}/out:${outputTokens} cost=$${costUsd.toFixed(4)} latencyMs=${Date.now() - startedAt}`
    );
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
