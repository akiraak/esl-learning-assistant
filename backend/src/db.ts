import fs from "fs";
import Database from "better-sqlite3";
import { config } from "./config";

fs.mkdirSync(config.imagesDir, { recursive: true });

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
