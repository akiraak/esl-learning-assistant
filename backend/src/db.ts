import fs from "fs";
import Database from "better-sqlite3";
import { config } from "./config";

fs.mkdirSync(config.imagesDir, { recursive: true });
fs.mkdirSync(config.ttsDir, { recursive: true });
fs.mkdirSync(config.audioDir, { recursive: true });
fs.mkdirSync(config.illustrationsDir, { recursive: true });

export const db = new Database(config.dbPath);
db.pragma("journal_mode = WAL");

db.exec(`
  CREATE TABLE IF NOT EXISTS requests (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    created_at TEXT NOT NULL,
    image_filename TEXT,
    target_language TEXT NOT NULL,
    ocr_text TEXT,
    translated_text TEXT,
    ocr_model TEXT NOT NULL,
    ocr_input_tokens INTEGER NOT NULL DEFAULT 0,
    ocr_output_tokens INTEGER NOT NULL DEFAULT 0,
    translate_model TEXT,
    translate_input_tokens INTEGER NOT NULL DEFAULT 0,
    translate_output_tokens INTEGER NOT NULL DEFAULT 0,
    ocr_cost_usd REAL NOT NULL DEFAULT 0,
    translate_cost_usd REAL NOT NULL DEFAULT 0,
    cost_usd REAL NOT NULL DEFAULT 0,
    status TEXT NOT NULL,
    error_message TEXT,
    latency_ms INTEGER NOT NULL DEFAULT 0
  )
`);

// OCR/翻訳を別モデル化する前のDBには model/input_tokens/output_tokens列しか無いため、
// 起動時にカラム有無を確認して後方互換マイグレーションする（既存ログを保持するため）。
const existingColumns = new Set(
  (db.prepare("PRAGMA table_info(requests)").all() as { name: string }[]).map((c) => c.name)
);
if (existingColumns.has("model") && !existingColumns.has("ocr_model")) {
  db.exec("ALTER TABLE requests RENAME COLUMN model TO ocr_model");
  db.exec("ALTER TABLE requests RENAME COLUMN input_tokens TO ocr_input_tokens");
  db.exec("ALTER TABLE requests RENAME COLUMN output_tokens TO ocr_output_tokens");
}
if (!existingColumns.has("translate_model")) {
  db.exec("ALTER TABLE requests ADD COLUMN translate_model TEXT");
  db.exec("ALTER TABLE requests ADD COLUMN translate_input_tokens INTEGER NOT NULL DEFAULT 0");
  db.exec("ALTER TABLE requests ADD COLUMN translate_output_tokens INTEGER NOT NULL DEFAULT 0");
}
if (!existingColumns.has("ocr_cost_usd")) {
  db.exec("ALTER TABLE requests ADD COLUMN ocr_cost_usd REAL NOT NULL DEFAULT 0");
  db.exec("ALTER TABLE requests ADD COLUMN translate_cost_usd REAL NOT NULL DEFAULT 0");
}

// 単語情報生成（/api/word-info）のログ。既存requestsテーブルはOCR専用構造のため分ける。
db.exec(`
  CREATE TABLE IF NOT EXISTS word_info_requests (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    created_at TEXT NOT NULL,
    word TEXT NOT NULL,
    target_language TEXT NOT NULL,
    user_translation TEXT,
    context TEXT,
    word_info_json TEXT,
    model TEXT NOT NULL,
    input_tokens INTEGER NOT NULL DEFAULT 0,
    output_tokens INTEGER NOT NULL DEFAULT 0,
    cost_usd REAL NOT NULL DEFAULT 0,
    status TEXT NOT NULL,
    error_message TEXT,
    latency_ms INTEGER NOT NULL DEFAULT 0,
    cache_hit INTEGER NOT NULL DEFAULT 0
  )
`);

// words テーブル導入前のDBには cache_hit 列が無いため後方互換マイグレーション
const wordInfoColumns = new Set(
  (db.prepare("PRAGMA table_info(word_info_requests)").all() as { name: string }[]).map((c) => c.name)
);
if (!wordInfoColumns.has("cache_hit")) {
  db.exec("ALTER TABLE word_info_requests ADD COLUMN cache_hit INTEGER NOT NULL DEFAULT 0");
}

// 作文添削（/api/writing-feedback）のログ。作文本文は毎回異なりキャッシュが効かないため
// サーバ側は保存せずログ用途のみ（結果本体の永続化は iOS 側 Composition.feedback）。
db.exec(`
  CREATE TABLE IF NOT EXISTS writing_feedback_requests (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    created_at TEXT NOT NULL,
    english_text TEXT NOT NULL,
    japanese_text TEXT NOT NULL,
    explanation_language TEXT NOT NULL,
    feedback_json TEXT,
    model TEXT NOT NULL,
    input_tokens INTEGER NOT NULL DEFAULT 0,
    output_tokens INTEGER NOT NULL DEFAULT 0,
    cost_usd REAL NOT NULL DEFAULT 0,
    status TEXT NOT NULL,
    error_message TEXT,
    latency_ms INTEGER NOT NULL DEFAULT 0
  )
`);

// サーバ合成したTTS音声の保存（実体は data/tts/<text_hash>.wav、ここはメタデータ）。
// キャッシュキーは sha256("model|text")（voice は生成時ランダム選択のためキーに含めない。
// 旧形式 sha256("voice|model|text") の既存行はヒットしなくなるが残置）。
db.exec(`
  CREATE TABLE IF NOT EXISTS tts_audio (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    created_at TEXT NOT NULL,
    text TEXT NOT NULL,
    voice TEXT NOT NULL,
    model TEXT NOT NULL,
    text_hash TEXT NOT NULL UNIQUE,
    filename TEXT NOT NULL,
    byte_size INTEGER NOT NULL,
    input_tokens INTEGER NOT NULL DEFAULT 0,
    output_tokens INTEGER NOT NULL DEFAULT 0,
    cost_usd REAL NOT NULL DEFAULT 0
  )
`);

// トークン・料金記録前のDBにはこれらの列が無いため後方互換マイグレーション。
// 既存行は input_tokens = output_tokens = 0 のままとなり「料金未記録」として扱う。
const ttsColumns = new Set(
  (db.prepare("PRAGMA table_info(tts_audio)").all() as { name: string }[]).map((c) => c.name)
);
if (!ttsColumns.has("input_tokens")) {
  db.exec("ALTER TABLE tts_audio ADD COLUMN input_tokens INTEGER NOT NULL DEFAULT 0");
  db.exec("ALTER TABLE tts_audio ADD COLUMN output_tokens INTEGER NOT NULL DEFAULT 0");
  db.exec("ALTER TABLE tts_audio ADD COLUMN cost_usd REAL NOT NULL DEFAULT 0");
}

// 単語イラスト（GPT Image 2 生成）の保存（実体は data/illustrations/<key_hash>.png、ここはメタデータ）。
// キャッシュキーは sha256("model|word|target_language|sense_index")。
// sense_index は自動生成では常に0（第1義）だが、将来「意味ごとに生成」に拡張できるようキーに含める。
db.exec(`
  CREATE TABLE IF NOT EXISTS word_illustrations (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    created_at TEXT NOT NULL,
    word TEXT NOT NULL,
    target_language TEXT NOT NULL,
    sense_index INTEGER NOT NULL DEFAULT 0,
    prompt TEXT NOT NULL,
    model TEXT NOT NULL,
    key_hash TEXT NOT NULL UNIQUE,
    filename TEXT NOT NULL,
    byte_size INTEGER NOT NULL,
    input_tokens INTEGER NOT NULL DEFAULT 0,
    output_tokens INTEGER NOT NULL DEFAULT 0,
    cost_usd REAL NOT NULL DEFAULT 0
  )
`);

// 音声文字起こし＋翻訳（/api/transcribe-translate）のログ。写真OCRの requests に倣った構造で、
// OCR→transcription に読み替えたもの。写真OCR同様サーバキャッシュは持たず、結果本体は
// iOS 側 AudioClip に保存する。ここは料金・履歴・管理画面での音声試聴のためのログ用途。
db.exec(`
  CREATE TABLE IF NOT EXISTS transcription_requests (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    created_at TEXT NOT NULL,
    audio_filename TEXT,
    media_type TEXT NOT NULL,
    target_language TEXT NOT NULL,
    byte_size INTEGER NOT NULL DEFAULT 0,
    english_text TEXT,
    translated_text TEXT,
    transcription_model TEXT NOT NULL,
    transcription_input_tokens INTEGER NOT NULL DEFAULT 0,
    transcription_output_tokens INTEGER NOT NULL DEFAULT 0,
    translate_model TEXT,
    translate_input_tokens INTEGER NOT NULL DEFAULT 0,
    translate_output_tokens INTEGER NOT NULL DEFAULT 0,
    transcription_cost_usd REAL NOT NULL DEFAULT 0,
    translate_cost_usd REAL NOT NULL DEFAULT 0,
    cost_usd REAL NOT NULL DEFAULT 0,
    status TEXT NOT NULL,
    error_message TEXT,
    latency_ms INTEGER NOT NULL DEFAULT 0
  )
`);

// 汎用のシステムイベントログ。料金チェック以外のイベントも今後ここに記録する。
db.exec(`
  CREATE TABLE IF NOT EXISTS system_logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    created_at TEXT NOT NULL,
    category TEXT NOT NULL,
    level TEXT NOT NULL,
    message TEXT NOT NULL
  )
`);

// 最後に適用したAI単価表（再起動時の復元と変更有無の比較に使う。1行のみ運用）。
db.exec(`
  CREATE TABLE IF NOT EXISTS pricing_state (
    id INTEGER PRIMARY KEY CHECK (id = 1),
    updated_at TEXT NOT NULL,
    prices_json TEXT NOT NULL
  )
`);

// 単語情報の正式な保存先（word_info_requests は通信ログとして温存し役割を分ける）。
// キャッシュキーは (trim + 小文字化した word, target_language)。
db.exec(`
  CREATE TABLE IF NOT EXISTS words (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    word TEXT NOT NULL,
    target_language TEXT NOT NULL,
    word_info_json TEXT NOT NULL,
    model TEXT NOT NULL,
    context TEXT,
    user_translation TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    generation_count INTEGER NOT NULL DEFAULT 1,
    UNIQUE(word, target_language)
  )
`);

// 復習クイズ問題（docs/plans/archive/quiz-questions-server-storage.md）。
// 1単語×1形式につき複数バリエーション（variant_index）を保存し、iOS がランダムに選んで出題する。
// question_json は iOS の ReviewQuestion と 1:1 対応。model はイラスト系のルール生成では "rule"。
db.exec(`
  CREATE TABLE IF NOT EXISTS quiz_questions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    created_at TEXT NOT NULL,
    word TEXT NOT NULL,
    target_language TEXT NOT NULL,
    format TEXT NOT NULL,
    variant_index INTEGER NOT NULL,
    question_json TEXT NOT NULL,
    model TEXT NOT NULL,
    input_tokens INTEGER NOT NULL DEFAULT 0,
    output_tokens INTEGER NOT NULL DEFAULT 0,
    cost_usd REAL NOT NULL DEFAULT 0,
    UNIQUE(word, target_language, format, variant_index)
  )
`);

// 廃止した穴埋めテキスト入力形式（tt2）の保存済み問題を一掃する
// （docs/plans/archive/remove-fill-blank-typing.md。冪等なので毎起動で実行してよい。
//   vtt1 は音声で答えを特定できるため復活: docs/plans/archive/restore-vtt1.md）。
db.exec("DELETE FROM quiz_questions WHERE format = 'tt2'");

export interface RequestLogInput {
  imageFilename: string | null;
  targetLanguage: string;
  ocrText: string | null;
  translatedText: string | null;
  ocrModel: string;
  ocrInputTokens: number;
  ocrOutputTokens: number;
  translateModel: string | null;
  translateInputTokens: number;
  translateOutputTokens: number;
  ocrCostUsd: number;
  translateCostUsd: number;
  costUsd: number;
  status: "success" | "error";
  errorMessage: string | null;
  latencyMs: number;
}

const insertStmt = db.prepare(`
  INSERT INTO requests (
    created_at, image_filename, target_language, ocr_text, translated_text,
    ocr_model, ocr_input_tokens, ocr_output_tokens,
    translate_model, translate_input_tokens, translate_output_tokens,
    ocr_cost_usd, translate_cost_usd, cost_usd, status, error_message, latency_ms
  ) VALUES (
    @createdAt, @imageFilename, @targetLanguage, @ocrText, @translatedText,
    @ocrModel, @ocrInputTokens, @ocrOutputTokens,
    @translateModel, @translateInputTokens, @translateOutputTokens,
    @ocrCostUsd, @translateCostUsd, @costUsd, @status, @errorMessage, @latencyMs
  )
`);

export function insertRequestLog(input: RequestLogInput): void {
  insertStmt.run({
    createdAt: new Date().toISOString(),
    imageFilename: input.imageFilename,
    targetLanguage: input.targetLanguage,
    ocrText: input.ocrText,
    translatedText: input.translatedText,
    ocrModel: input.ocrModel,
    ocrInputTokens: input.ocrInputTokens,
    ocrOutputTokens: input.ocrOutputTokens,
    translateModel: input.translateModel,
    translateInputTokens: input.translateInputTokens,
    translateOutputTokens: input.translateOutputTokens,
    ocrCostUsd: input.ocrCostUsd,
    translateCostUsd: input.translateCostUsd,
    costUsd: input.costUsd,
    status: input.status,
    errorMessage: input.errorMessage,
    latencyMs: input.latencyMs,
  });
}

export interface RequestLogRow {
  id: number;
  created_at: string;
  image_filename: string | null;
  target_language: string;
  ocr_text: string | null;
  translated_text: string | null;
  ocr_model: string;
  ocr_input_tokens: number;
  ocr_output_tokens: number;
  translate_model: string | null;
  translate_input_tokens: number;
  translate_output_tokens: number;
  ocr_cost_usd: number;
  translate_cost_usd: number;
  cost_usd: number;
  status: string;
  error_message: string | null;
  latency_ms: number;
}

export function listRecentRequestLogs(limit: number): RequestLogRow[] {
  return db
    .prepare("SELECT * FROM requests ORDER BY id DESC LIMIT ?")
    .all(limit) as RequestLogRow[];
}

export function getRequestLog(id: number): RequestLogRow | undefined {
  return db.prepare("SELECT * FROM requests WHERE id = ?").get(id) as RequestLogRow | undefined;
}

export interface WordInfoLogInput {
  word: string;
  targetLanguage: string;
  userTranslation: string | null;
  context: string | null;
  wordInfoJson: string | null;
  model: string;
  inputTokens: number;
  outputTokens: number;
  costUsd: number;
  status: "success" | "error";
  errorMessage: string | null;
  latencyMs: number;
  cacheHit: boolean;
}

const insertWordInfoStmt = db.prepare(`
  INSERT INTO word_info_requests (
    created_at, word, target_language, user_translation, context,
    word_info_json, model, input_tokens, output_tokens,
    cost_usd, status, error_message, latency_ms, cache_hit
  ) VALUES (
    @createdAt, @word, @targetLanguage, @userTranslation, @context,
    @wordInfoJson, @model, @inputTokens, @outputTokens,
    @costUsd, @status, @errorMessage, @latencyMs, @cacheHit
  )
`);

export function insertWordInfoLog(input: WordInfoLogInput): void {
  insertWordInfoStmt.run({
    createdAt: new Date().toISOString(),
    word: input.word,
    targetLanguage: input.targetLanguage,
    userTranslation: input.userTranslation,
    context: input.context,
    wordInfoJson: input.wordInfoJson,
    model: input.model,
    inputTokens: input.inputTokens,
    outputTokens: input.outputTokens,
    costUsd: input.costUsd,
    status: input.status,
    errorMessage: input.errorMessage,
    latencyMs: input.latencyMs,
    cacheHit: input.cacheHit ? 1 : 0,
  });
}

export interface WordInfoLogRow {
  id: number;
  created_at: string;
  word: string;
  target_language: string;
  user_translation: string | null;
  context: string | null;
  word_info_json: string | null;
  model: string;
  input_tokens: number;
  output_tokens: number;
  cost_usd: number;
  status: string;
  error_message: string | null;
  latency_ms: number;
  cache_hit: number;
}

export function listRecentWordInfoLogs(limit: number): WordInfoLogRow[] {
  return db
    .prepare("SELECT * FROM word_info_requests ORDER BY id DESC LIMIT ?")
    .all(limit) as WordInfoLogRow[];
}

export function getWordInfoLog(id: number): WordInfoLogRow | undefined {
  return db
    .prepare("SELECT * FROM word_info_requests WHERE id = ?")
    .get(id) as WordInfoLogRow | undefined;
}

export interface WritingFeedbackLogInput {
  englishText: string;
  japaneseText: string;
  explanationLanguage: string;
  feedbackJson: string | null;
  model: string;
  inputTokens: number;
  outputTokens: number;
  costUsd: number;
  status: "success" | "error";
  errorMessage: string | null;
  latencyMs: number;
}

const insertWritingFeedbackStmt = db.prepare(`
  INSERT INTO writing_feedback_requests (
    created_at, english_text, japanese_text, explanation_language,
    feedback_json, model, input_tokens, output_tokens,
    cost_usd, status, error_message, latency_ms
  ) VALUES (
    @createdAt, @englishText, @japaneseText, @explanationLanguage,
    @feedbackJson, @model, @inputTokens, @outputTokens,
    @costUsd, @status, @errorMessage, @latencyMs
  )
`);

export function insertWritingFeedbackLog(input: WritingFeedbackLogInput): void {
  insertWritingFeedbackStmt.run({
    createdAt: new Date().toISOString(),
    englishText: input.englishText,
    japaneseText: input.japaneseText,
    explanationLanguage: input.explanationLanguage,
    feedbackJson: input.feedbackJson,
    model: input.model,
    inputTokens: input.inputTokens,
    outputTokens: input.outputTokens,
    costUsd: input.costUsd,
    status: input.status,
    errorMessage: input.errorMessage,
    latencyMs: input.latencyMs,
  });
}

export interface WritingFeedbackLogRow {
  id: number;
  created_at: string;
  english_text: string;
  japanese_text: string;
  explanation_language: string;
  feedback_json: string | null;
  model: string;
  input_tokens: number;
  output_tokens: number;
  cost_usd: number;
  status: string;
  error_message: string | null;
  latency_ms: number;
}

export function listRecentWritingFeedbackLogs(limit: number): WritingFeedbackLogRow[] {
  return db
    .prepare("SELECT * FROM writing_feedback_requests ORDER BY id DESC LIMIT ?")
    .all(limit) as WritingFeedbackLogRow[];
}

export function getWritingFeedbackLog(id: number): WritingFeedbackLogRow | undefined {
  return db
    .prepare("SELECT * FROM writing_feedback_requests WHERE id = ?")
    .get(id) as WritingFeedbackLogRow | undefined;
}

export interface TranscriptionLogInput {
  audioFilename: string | null;
  mediaType: string;
  targetLanguage: string;
  byteSize: number;
  englishText: string | null;
  translatedText: string | null;
  transcriptionModel: string;
  transcriptionInputTokens: number;
  transcriptionOutputTokens: number;
  translateModel: string | null;
  translateInputTokens: number;
  translateOutputTokens: number;
  transcriptionCostUsd: number;
  translateCostUsd: number;
  costUsd: number;
  status: "success" | "error";
  errorMessage: string | null;
  latencyMs: number;
}

const insertTranscriptionStmt = db.prepare(`
  INSERT INTO transcription_requests (
    created_at, audio_filename, media_type, target_language, byte_size,
    english_text, translated_text,
    transcription_model, transcription_input_tokens, transcription_output_tokens,
    translate_model, translate_input_tokens, translate_output_tokens,
    transcription_cost_usd, translate_cost_usd, cost_usd, status, error_message, latency_ms
  ) VALUES (
    @createdAt, @audioFilename, @mediaType, @targetLanguage, @byteSize,
    @englishText, @translatedText,
    @transcriptionModel, @transcriptionInputTokens, @transcriptionOutputTokens,
    @translateModel, @translateInputTokens, @translateOutputTokens,
    @transcriptionCostUsd, @translateCostUsd, @costUsd, @status, @errorMessage, @latencyMs
  )
`);

export function insertTranscriptionLog(input: TranscriptionLogInput): void {
  insertTranscriptionStmt.run({
    createdAt: new Date().toISOString(),
    audioFilename: input.audioFilename,
    mediaType: input.mediaType,
    targetLanguage: input.targetLanguage,
    byteSize: input.byteSize,
    englishText: input.englishText,
    translatedText: input.translatedText,
    transcriptionModel: input.transcriptionModel,
    transcriptionInputTokens: input.transcriptionInputTokens,
    transcriptionOutputTokens: input.transcriptionOutputTokens,
    translateModel: input.translateModel,
    translateInputTokens: input.translateInputTokens,
    translateOutputTokens: input.translateOutputTokens,
    transcriptionCostUsd: input.transcriptionCostUsd,
    translateCostUsd: input.translateCostUsd,
    costUsd: input.costUsd,
    status: input.status,
    errorMessage: input.errorMessage,
    latencyMs: input.latencyMs,
  });
}

export interface TranscriptionLogRow {
  id: number;
  created_at: string;
  audio_filename: string | null;
  media_type: string;
  target_language: string;
  byte_size: number;
  english_text: string | null;
  translated_text: string | null;
  transcription_model: string;
  transcription_input_tokens: number;
  transcription_output_tokens: number;
  translate_model: string | null;
  translate_input_tokens: number;
  translate_output_tokens: number;
  transcription_cost_usd: number;
  translate_cost_usd: number;
  cost_usd: number;
  status: string;
  error_message: string | null;
  latency_ms: number;
}

export function listRecentTranscriptionLogs(limit: number): TranscriptionLogRow[] {
  return db
    .prepare("SELECT * FROM transcription_requests ORDER BY id DESC LIMIT ?")
    .all(limit) as TranscriptionLogRow[];
}

export function getTranscriptionLog(id: number): TranscriptionLogRow | undefined {
  return db
    .prepare("SELECT * FROM transcription_requests WHERE id = ?")
    .get(id) as TranscriptionLogRow | undefined;
}

export function deleteTranscriptionLog(id: number): void {
  db.prepare("DELETE FROM transcription_requests WHERE id = ?").run(id);
}

export interface StoredWordRow {
  id: number;
  word: string;
  target_language: string;
  word_info_json: string;
  model: string;
  context: string | null;
  user_translation: string | null;
  created_at: string;
  updated_at: string;
  generation_count: number;
}

/// キャッシュキー正規化（"Apple" と "apple" は同一エントリとする割り切り）
export function normalizeWordKey(word: string): string {
  return word.trim().toLowerCase();
}

export function getStoredWord(word: string, targetLanguage: string): StoredWordRow | undefined {
  return db
    .prepare("SELECT * FROM words WHERE word = ? AND target_language = ?")
    .get(normalizeWordKey(word), targetLanguage) as StoredWordRow | undefined;
}

export function getStoredWordById(id: number): StoredWordRow | undefined {
  return db.prepare("SELECT * FROM words WHERE id = ?").get(id) as StoredWordRow | undefined;
}

export function listStoredWords(): StoredWordRow[] {
  return db.prepare("SELECT * FROM words ORDER BY updated_at DESC, id DESC").all() as StoredWordRow[];
}

export interface StoredWordInput {
  word: string;
  targetLanguage: string;
  wordInfoJson: string;
  model: string;
  context: string | null;
  userTranslation: string | null;
}

const upsertStoredWordStmt = db.prepare(`
  INSERT INTO words (
    word, target_language, word_info_json, model, context, user_translation,
    created_at, updated_at, generation_count
  ) VALUES (
    @word, @targetLanguage, @wordInfoJson, @model, @context, @userTranslation,
    @now, @now, 1
  )
  ON CONFLICT(word, target_language) DO UPDATE SET
    word_info_json = excluded.word_info_json,
    model = excluded.model,
    context = excluded.context,
    user_translation = excluded.user_translation,
    updated_at = excluded.updated_at,
    generation_count = generation_count + 1
`);

/// 生成結果を保存する。同一キーが既にあれば内容を更新して generation_count を加算する（後勝ち）。
export function upsertStoredWord(input: StoredWordInput): void {
  upsertStoredWordStmt.run({
    word: normalizeWordKey(input.word),
    targetLanguage: input.targetLanguage,
    wordInfoJson: input.wordInfoJson,
    model: input.model,
    context: input.context,
    userTranslation: input.userTranslation,
    now: new Date().toISOString(),
  });
}

export function deleteStoredWord(id: number): void {
  db.prepare("DELETE FROM words WHERE id = ?").run(id);
}

export interface TtsAudioRow {
  id: number;
  created_at: string;
  text: string;
  voice: string;
  model: string;
  text_hash: string;
  filename: string;
  byte_size: number;
  input_tokens: number;
  output_tokens: number;
  cost_usd: number;
}

export function getTtsAudioByHash(textHash: string): TtsAudioRow | undefined {
  return db.prepare("SELECT * FROM tts_audio WHERE text_hash = ?").get(textHash) as TtsAudioRow | undefined;
}

export function getTtsAudioById(id: number): TtsAudioRow | undefined {
  return db.prepare("SELECT * FROM tts_audio WHERE id = ?").get(id) as TtsAudioRow | undefined;
}

export function listTtsAudio(): TtsAudioRow[] {
  return db.prepare("SELECT * FROM tts_audio ORDER BY id DESC").all() as TtsAudioRow[];
}

const upsertTtsAudioStmt = db.prepare(`
  INSERT INTO tts_audio (created_at, text, voice, model, text_hash, filename, byte_size, input_tokens, output_tokens, cost_usd)
  VALUES (@createdAt, @text, @voice, @model, @textHash, @filename, @byteSize, @inputTokens, @outputTokens, @costUsd)
  ON CONFLICT(text_hash) DO UPDATE SET
    created_at = excluded.created_at,
    byte_size = excluded.byte_size,
    input_tokens = excluded.input_tokens,
    output_tokens = excluded.output_tokens,
    cost_usd = excluded.cost_usd
`);

/// 合成結果のメタデータを保存する。ファイル欠損からの自己修復（再合成）時は既存行を更新する
/// （トークン数・料金も再合成時の値で上書きする）。
export function upsertTtsAudio(input: {
  text: string;
  voice: string;
  model: string;
  textHash: string;
  filename: string;
  byteSize: number;
  inputTokens: number;
  outputTokens: number;
  costUsd: number;
}): void {
  upsertTtsAudioStmt.run({
    createdAt: new Date().toISOString(),
    text: input.text,
    voice: input.voice,
    model: input.model,
    textHash: input.textHash,
    filename: input.filename,
    byteSize: input.byteSize,
    inputTokens: input.inputTokens,
    outputTokens: input.outputTokens,
    costUsd: input.costUsd,
  });
}

export function deleteTtsAudio(id: number): void {
  db.prepare("DELETE FROM tts_audio WHERE id = ?").run(id);
}

export interface WordIllustrationRow {
  id: number;
  created_at: string;
  word: string;
  target_language: string;
  sense_index: number;
  prompt: string;
  model: string;
  key_hash: string;
  filename: string;
  byte_size: number;
  input_tokens: number;
  output_tokens: number;
  cost_usd: number;
}

export function getWordIllustrationByHash(keyHash: string): WordIllustrationRow | undefined {
  return db
    .prepare("SELECT * FROM word_illustrations WHERE key_hash = ?")
    .get(keyHash) as WordIllustrationRow | undefined;
}

export function getWordIllustrationById(id: number): WordIllustrationRow | undefined {
  return db.prepare("SELECT * FROM word_illustrations WHERE id = ?").get(id) as WordIllustrationRow | undefined;
}

export function listWordIllustrations(): WordIllustrationRow[] {
  return db.prepare("SELECT * FROM word_illustrations ORDER BY id DESC").all() as WordIllustrationRow[];
}

const upsertWordIllustrationStmt = db.prepare(`
  INSERT INTO word_illustrations (
    created_at, word, target_language, sense_index, prompt, model,
    key_hash, filename, byte_size, input_tokens, output_tokens, cost_usd
  ) VALUES (
    @createdAt, @word, @targetLanguage, @senseIndex, @prompt, @model,
    @keyHash, @filename, @byteSize, @inputTokens, @outputTokens, @costUsd
  )
  ON CONFLICT(key_hash) DO UPDATE SET
    created_at = excluded.created_at,
    prompt = excluded.prompt,
    byte_size = excluded.byte_size,
    input_tokens = excluded.input_tokens,
    output_tokens = excluded.output_tokens,
    cost_usd = excluded.cost_usd
`);

/// 生成結果のメタデータを保存する。ファイル欠損からの自己修復・管理画面からの再生成時は
/// 既存行を更新する（トークン数・料金も再生成時の値で上書きする）。
export function upsertWordIllustration(input: {
  word: string;
  targetLanguage: string;
  senseIndex: number;
  prompt: string;
  model: string;
  keyHash: string;
  filename: string;
  byteSize: number;
  inputTokens: number;
  outputTokens: number;
  costUsd: number;
}): void {
  upsertWordIllustrationStmt.run({
    createdAt: new Date().toISOString(),
    word: input.word,
    targetLanguage: input.targetLanguage,
    senseIndex: input.senseIndex,
    prompt: input.prompt,
    model: input.model,
    keyHash: input.keyHash,
    filename: input.filename,
    byteSize: input.byteSize,
    inputTokens: input.inputTokens,
    outputTokens: input.outputTokens,
    costUsd: input.costUsd,
  });
}

export function deleteWordIllustration(id: number): void {
  db.prepare("DELETE FROM word_illustrations WHERE id = ?").run(id);
}

export interface QuizQuestionRow {
  id: number;
  created_at: string;
  word: string;
  target_language: string;
  format: string;
  variant_index: number;
  question_json: string;
  model: string;
  input_tokens: number;
  output_tokens: number;
  cost_usd: number;
}

export interface QuizQuestionInput {
  word: string;
  targetLanguage: string;
  format: string;
  variantIndex: number;
  questionJson: string;
  model: string;
  inputTokens: number;
  outputTokens: number;
  costUsd: number;
}

const insertQuizQuestionStmt = db.prepare(`
  INSERT INTO quiz_questions (
    created_at, word, target_language, format, variant_index,
    question_json, model, input_tokens, output_tokens, cost_usd
  ) VALUES (
    @createdAt, @word, @targetLanguage, @format, @variantIndex,
    @questionJson, @model, @inputTokens, @outputTokens, @costUsd
  )
`);

const deleteQuizQuestionsStmt = db.prepare(
  "DELETE FROM quiz_questions WHERE word = ? AND target_language = ?"
);

/// 1単語分の問題を丸ごと置き換える（部分更新はしない。再生成時も同じ経路）
export const replaceQuizQuestions = db.transaction(
  (word: string, targetLanguage: string, questions: QuizQuestionInput[]) => {
    deleteQuizQuestionsStmt.run(normalizeWordKey(word), targetLanguage);
    const now = new Date().toISOString();
    for (const question of questions) {
      insertQuizQuestionStmt.run({
        createdAt: now,
        word: normalizeWordKey(question.word),
        targetLanguage: question.targetLanguage,
        format: question.format,
        variantIndex: question.variantIndex,
        questionJson: question.questionJson,
        model: question.model,
        inputTokens: question.inputTokens,
        outputTokens: question.outputTokens,
        costUsd: question.costUsd,
      });
    }
  }
);

export function listQuizQuestions(word: string, targetLanguage: string): QuizQuestionRow[] {
  return db
    .prepare(
      "SELECT * FROM quiz_questions WHERE word = ? AND target_language = ? ORDER BY format, variant_index"
    )
    .all(normalizeWordKey(word), targetLanguage) as QuizQuestionRow[];
}

export function countQuizQuestions(word: string, targetLanguage: string): number {
  const row = db
    .prepare("SELECT COUNT(*) AS count FROM quiz_questions WHERE word = ? AND target_language = ?")
    .get(normalizeWordKey(word), targetLanguage) as { count: number };
  return row.count;
}

export function deleteQuizQuestions(word: string, targetLanguage: string): void {
  deleteQuizQuestionsStmt.run(normalizeWordKey(word), targetLanguage);
}

export interface QuizQuestionSummaryRow {
  word: string;
  target_language: string;
  question_count: number;
  format_count: number;
  total_cost_usd: number;
  latest_created_at: string;
}

/// 管理画面用: 単語×言語ごとの問題数・形式数・コスト合計
export function listQuizQuestionSummaries(): QuizQuestionSummaryRow[] {
  return db
    .prepare(`
      SELECT word, target_language,
        COUNT(*) AS question_count,
        COUNT(DISTINCT format) AS format_count,
        SUM(cost_usd) AS total_cost_usd,
        MAX(created_at) AS latest_created_at
      FROM quiz_questions
      GROUP BY word, target_language
      ORDER BY latest_created_at DESC
    `)
    .all() as QuizQuestionSummaryRow[];
}

/// イラスト生成済みの単語一覧（イラスト系形式の誤答プール。sense_index は不問）
export function listIllustratedWords(targetLanguage: string): string[] {
  return (
    db
      .prepare("SELECT DISTINCT word FROM word_illustrations WHERE target_language = ?")
      .all(targetLanguage) as { word: string }[]
  ).map((row) => row.word);
}

/// words テーブルの単語テキスト一覧（イラスト系 IC1 の誤答プール）
export function listStoredWordTexts(targetLanguage: string): string[] {
  return (
    db.prepare("SELECT word FROM words WHERE target_language = ?").all(targetLanguage) as {
      word: string;
    }[]
  ).map((row) => row.word);
}

export type SystemLogLevel = "info" | "warn" | "error";

export interface SystemLogRow {
  id: number;
  created_at: string;
  category: string;
  level: string;
  message: string;
}

export function insertSystemLog(category: string, level: SystemLogLevel, message: string): void {
  db.prepare("INSERT INTO system_logs (created_at, category, level, message) VALUES (?, ?, ?, ?)").run(
    new Date().toISOString(),
    category,
    level,
    message
  );
}

export function listRecentSystemLogs(limit: number): SystemLogRow[] {
  return db.prepare("SELECT * FROM system_logs ORDER BY id DESC LIMIT ?").all(limit) as SystemLogRow[];
}

export interface PricingStateRow {
  id: number;
  updated_at: string;
  prices_json: string;
}

export function getPricingState(): PricingStateRow | undefined {
  return db.prepare("SELECT * FROM pricing_state WHERE id = 1").get() as PricingStateRow | undefined;
}

export function savePricingState(pricesJson: string): void {
  db.prepare(`
    INSERT INTO pricing_state (id, updated_at, prices_json) VALUES (1, @updatedAt, @pricesJson)
    ON CONFLICT(id) DO UPDATE SET updated_at = excluded.updated_at, prices_json = excluded.prices_json
  `).run({ updatedAt: new Date().toISOString(), pricesJson });
}
