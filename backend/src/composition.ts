// 作文（compositions）まわりの、DB にも HTTP にも依存しない定数・整形。
// admin.ts は db.ts を読み込むためテストから import できないので、
// 純粋な部分はここに置いて backend/test から直接検証する（compositionView.ts と同じ方針）。

/// 本文（英文・意図）1 つあたりの上限文字数。保存・綴り検査の受け口で共通に使う。
export const WRITING_TEXT_MAX_LENGTH = 5000;

/// 作文を新規作成するときの解説言語（現状は日本語固定）。
export const DEFAULT_EXPLANATION_LANGUAGE = "ja";

/// 1作文あたりのページ（タブ）数の上限。これ以上はタブ列に並べきれないので「＋」を止める。
export const COMPOSITION_PAGES_MAX = 20;

/// タブ名の上限文字数。
export const PAGE_NAME_MAX_LENGTH = 40;

/// タブ名の整形（改行は空白に潰し、前後の空白を落とし、上限で切る）。
/// 空文字も許す（そのときタブには「ページ N」を出す）。
export function sanitizePageName(raw: string): string {
  return raw.replace(/[\r\n]+/g, " ").replace(/\s+/g, " ").trim().slice(0, PAGE_NAME_MAX_LENGTH);
}

/// タブに出す表示名。名前が空なら並び順から「ページ N」を作る。
export function pageDisplayName(name: string, position: number): string {
  return name.trim() || `ページ ${position}`;
}
