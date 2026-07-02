import path from "path";

export const config = {
  port: Number(process.env.PORT ?? 8801),
  anthropicApiKey: process.env.ANTHROPIC_API_KEY ?? "",
  ocrModel: process.env.ANTHROPIC_MODEL ?? "claude-sonnet-5",
  translateModel: process.env.ANTHROPIC_TRANSLATE_MODEL ?? "claude-haiku-4-5",
  wordInfoModel: process.env.ANTHROPIC_WORD_INFO_MODEL ?? "claude-haiku-4-5",
  geminiApiKey: process.env.GEMINI_API_KEY ?? "",
  apiSecret: process.env.API_SECRET ?? "",
  dataDir: path.resolve(__dirname, "..", "data"),
  imagesDir: path.resolve(__dirname, "..", "data", "images"),
  dbPath: path.resolve(__dirname, "..", "data", "db.sqlite"),
};
