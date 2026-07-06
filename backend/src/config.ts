import path from "path";

export const config = {
  port: Number(process.env.PORT ?? 8801),
  anthropicApiKey: process.env.ANTHROPIC_API_KEY ?? "",
  ocrModel: process.env.ANTHROPIC_MODEL ?? "claude-sonnet-5",
  translateModel: process.env.ANTHROPIC_TRANSLATE_MODEL ?? "claude-haiku-4-5",
  wordInfoModel: process.env.ANTHROPIC_WORD_INFO_MODEL ?? "claude-haiku-4-5",
  quizQuestionModel: process.env.ANTHROPIC_QUIZ_QUESTION_MODEL ?? "claude-haiku-4-5",
  // 作文添削は誤りの意図理解・自然な言い換えの質が学習効果に直結するため、
  // 単語情報（haiku）より一段強いモデルを既定にする。件数が少なくコスト影響は小さい。
  writingFeedbackModel: process.env.ANTHROPIC_WRITING_FEEDBACK_MODEL ?? "claude-sonnet-5",
  // 音声→英文の文字起こしは音声入力ネイティブ対応の Gemini で行う（Claude は音声入力不可）。
  // TTS とは別モデル（テキスト出力）なので TTS 用変数とは分ける。
  transcriptionModel: process.env.GEMINI_TRANSCRIPTION_MODEL ?? "gemini-2.5-flash",
  geminiApiKey: process.env.GEMINI_API_KEY ?? "",
  openaiApiKey: process.env.OPENAI_API_KEY ?? "",
  apiSecret: process.env.API_SECRET ?? "",
  dataDir: path.resolve(__dirname, "..", "data"),
  imagesDir: path.resolve(__dirname, "..", "data", "images"),
  ttsDir: path.resolve(__dirname, "..", "data", "tts"),
  audioDir: path.resolve(__dirname, "..", "data", "audio"),
  illustrationsDir: path.resolve(__dirname, "..", "data", "illustrations"),
  dbPath: path.resolve(__dirname, "..", "data", "db.sqlite"),
};
