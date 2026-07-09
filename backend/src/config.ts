import path from "path";

// テスト（test/*.test.ts）が実データを汚さず一時ディレクトリへ隔離するための上書き。
// 通常運用では未設定のまま backend/data を使う。
const dataDir = process.env.DATA_DIR
  ? path.resolve(process.env.DATA_DIR)
  : path.resolve(__dirname, "..", "data");

export const config = {
  port: Number(process.env.PORT ?? 8801),
  anthropicApiKey: process.env.ANTHROPIC_API_KEY ?? "",
  ocrModel: process.env.ANTHROPIC_MODEL ?? "claude-sonnet-5",
  translateModel: process.env.ANTHROPIC_TRANSLATE_MODEL ?? "claude-haiku-4-5",
  wordInfoModel: process.env.ANTHROPIC_WORD_INFO_MODEL ?? "claude-haiku-4-5",
  // 入力語の正規化（原形化・綴り訂正）。小さなタスクなので安価・高速な haiku 単発で足りる。
  wordNormalizeModel: process.env.ANTHROPIC_WORD_NORMALIZE_MODEL ?? "claude-haiku-4-5",
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
  dataDir,
  imagesDir: path.join(dataDir, "images"),
  ttsDir: path.join(dataDir, "tts"),
  audioDir: path.join(dataDir, "audio"),
  documentsDir: path.join(dataDir, "documents"),
  illustrationsDir: path.join(dataDir, "illustrations"),
  dbPath: path.join(dataDir, "db.sqlite"),
};
