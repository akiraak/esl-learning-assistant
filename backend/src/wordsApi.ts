// 保存済み単語情報の参照 API（GET /api/words / GET /api/words/:word）の
// クエリパラメータ検証とレスポンス整形（docs/plans/word-info-reference-api.md）。
// HTTP・DB に依存しない純粋関数に分離して単体テスト可能にしている。
// import type のみ（実行時に db.ts / wordInfo.ts の副作用を持ち込まない）。
import type { StoredWordQuery, StoredWordRow } from "./db";
import type { WordInfo } from "./wordInfo";

export const WORD_LIST_LIMIT_DEFAULT = 100;
export const WORD_LIST_LIMIT_MAX = 500;

export type ParseResult<T> = { ok: true; value: T } | { ok: false; error: string };

export interface WordListQuery extends StoredWordQuery {
  includeInfo: boolean;
}

/// 0以上の整数文字列のみ受け付ける（"12abc" や小数を Number() の緩い変換で通さない）
function parseNonNegativeInt(raw: string): number | null {
  if (!/^\d+$/.test(raw)) return null;
  const value = Number(raw);
  return Number.isSafeInteger(value) ? value : null;
}

/// GET /api/words のクエリパラメータを検証してデフォルト値を適用する。
/// express の req.query は string 以外（配列等）も来うるため unknown として受ける。
export function parseWordListQuery(raw: Record<string, unknown>): ParseResult<WordListQuery> {
  const { targetLanguage, q, updatedSince, limit, offset, includeInfo } = raw;

  const query: WordListQuery = {
    limit: WORD_LIST_LIMIT_DEFAULT,
    offset: 0,
    includeInfo: false,
  };

  if (targetLanguage !== undefined) {
    if (typeof targetLanguage !== "string" || !targetLanguage.trim()) {
      return { ok: false, error: "targetLanguage must be a non-empty string" };
    }
    query.targetLanguage = targetLanguage.trim();
  }
  if (q !== undefined) {
    if (typeof q !== "string" || !q.trim()) {
      return { ok: false, error: "q must be a non-empty string" };
    }
    query.q = q.trim();
  }
  if (updatedSince !== undefined) {
    if (typeof updatedSince !== "string" || Number.isNaN(Date.parse(updatedSince))) {
      return { ok: false, error: "updatedSince must be an ISO 8601 date string" };
    }
    // DB の updated_at（UTC ISO）と辞書順比較できるよう UTC ISO に正規化する
    query.updatedSince = new Date(updatedSince).toISOString();
  }
  if (limit !== undefined) {
    const parsed = typeof limit === "string" ? parseNonNegativeInt(limit) : null;
    if (parsed === null || parsed < 1 || parsed > WORD_LIST_LIMIT_MAX) {
      return { ok: false, error: `limit must be an integer between 1 and ${WORD_LIST_LIMIT_MAX}` };
    }
    query.limit = parsed;
  }
  if (offset !== undefined) {
    const parsed = typeof offset === "string" ? parseNonNegativeInt(offset) : null;
    if (parsed === null) {
      return { ok: false, error: "offset must be a non-negative integer" };
    }
    query.offset = parsed;
  }
  if (includeInfo !== undefined) {
    if (includeInfo !== "true" && includeInfo !== "false") {
      return { ok: false, error: "includeInfo must be true or false" };
    }
    query.includeInfo = includeInfo === "true";
  }

  return { ok: true, value: query };
}

/// word_info_json を防御的にパースする。壊れていても一覧応答を落とさないため null を返す。
function parseWordInfoJson(json: string): WordInfo | null {
  try {
    const parsed: unknown = JSON.parse(json);
    if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) return null;
    return parsed as WordInfo;
  } catch {
    return null;
  }
}

export interface WordSummary {
  word: string;
  targetLanguage: string;
  meaning: string | null;
  partOfSpeech: string | null;
  cefrLevel: string | null;
  createdAt: string;
  updatedAt: string;
  wordInfo?: WordInfo | null;
}

/// 一覧用サマリ。meaning / partOfSpeech は第1義から取り出す。
/// includeInfo=true のときは wordInfo 全体も含める（壊れた JSON は null）。
export function buildWordSummary(row: StoredWordRow, includeInfo: boolean): WordSummary {
  const info = parseWordInfoJson(row.word_info_json);
  const firstSense = Array.isArray(info?.senses) ? info.senses[0] : undefined;
  const summary: WordSummary = {
    word: row.word,
    targetLanguage: row.target_language,
    meaning: typeof firstSense?.meaning === "string" ? firstSense.meaning : null,
    partOfSpeech: typeof firstSense?.partOfSpeech === "string" ? firstSense.partOfSpeech : null,
    cefrLevel: typeof info?.cefrLevel === "string" ? info.cefrLevel : null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
  if (includeInfo) {
    summary.wordInfo = info;
  }
  return summary;
}

export interface WordDetail {
  word: string;
  targetLanguage: string;
  wordInfo: WordInfo;
  model: string;
  createdAt: string;
  updatedAt: string;
  generationCount: number;
}

/// 詳細用整形。word_info_json が壊れている場合は null（ルート側で 500 にする）。
export function buildWordDetail(row: StoredWordRow): WordDetail | null {
  const info = parseWordInfoJson(row.word_info_json);
  if (!info) return null;
  return {
    word: row.word,
    targetLanguage: row.target_language,
    wordInfo: info,
    model: row.model,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    generationCount: row.generation_count,
  };
}
