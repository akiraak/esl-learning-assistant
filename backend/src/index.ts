import "dotenv/config";
import fs from "fs";
import path from "path";
import crypto from "crypto";
import express from "express";
import { config } from "./config";
import { insertRequestLog } from "./db";
import { adminRouter } from "./admin";
import { ocrAndTranslate } from "./ocrTranslate";
import { estimateCostUsd } from "./pricing";
import { logger } from "./logger";

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

app.use("/admin", adminRouter);

app.listen(config.port, () => {
  if (!config.anthropicApiKey) {
    logger.warn("ANTHROPIC_API_KEY is not set. /api/ocr-translate will fail.");
  }
  logger.info(`ESL Learning Assistant backend listening on http://localhost:${config.port}`);
  logger.info(`Admin dashboard: http://localhost:${config.port}/admin`);
  logger.info(`Log file: ${path.join(config.dataDir, "server.log")}`);
});
