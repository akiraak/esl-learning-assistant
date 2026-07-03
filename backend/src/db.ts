import fs from "fs";
import Database from "better-sqlite3";
import { config } from "./config";

fs.mkdirSync(config.imagesDir, { recursive: true });
fs.mkdirSync(config.ttsDir, { recursive: true });

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

// サーバ合成したTTS音声の保存（実体は data/tts/<text_hash>.wav、ここはメタデータ）。
// キャッシュキーは sha256("voice|model|text")。
db.exec(`
  CREATE TABLE IF NOT EXISTS tts_audio (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    created_at TEXT NOT NULL,
    text TEXT NOT NULL,
    voice TEXT NOT NULL,
    model TEXT NOT NULL,
    text_hash TEXT NOT NULL UNIQUE,
    filename TEXT NOT NULL,
    byte_size INTEGER NOT NULL
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
  INSERT INTO tts_audio (created_at, text, voice, model, text_hash, filename, byte_size)
  VALUES (@createdAt, @text, @voice, @model, @textHash, @filename, @byteSize)
  ON CONFLICT(text_hash) DO UPDATE SET
    created_at = excluded.created_at,
    byte_size = excluded.byte_size
`);

/// 合成結果のメタデータを保存する。ファイル欠損からの自己修復（再合成）時は既存行を更新する。
export function upsertTtsAudio(input: {
  text: string;
  voice: string;
  model: string;
  textHash: string;
  filename: string;
  byteSize: number;
}): void {
  upsertTtsAudioStmt.run({
    createdAt: new Date().toISOString(),
    text: input.text,
    voice: input.voice,
    model: input.model,
    textHash: input.textHash,
    filename: input.filename,
    byteSize: input.byteSize,
  });
}

export function deleteTtsAudio(id: number): void {
  db.prepare("DELETE FROM tts_audio WHERE id = ?").run(id);
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
