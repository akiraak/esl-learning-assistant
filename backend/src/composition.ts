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

/// 選択範囲の翻訳（docs/plans/writing-selection-translate.md）で 1 回に訳せる上限文字数。
/// 画面はこれを超える選択では通信せず注意文を出し、サーバも同じ値で弾く。
export const WRITING_TRANSLATE_MAX_LENGTH = 1000;

/// 選択範囲の翻訳でモデルへ添える前後の文脈の長さ（各方向）。
export const WRITING_TRANSLATE_CONTEXT_CHARS = 200;

/// 語数の数え方（執筆画面の右上に出すワード数）。文字か数字のかたまりを1語とし、
/// 語中のアポストロフィ・ハイフンは繋いだままにする（don't / well-known は 1 語）。
/// 画面側の JS もこの正規表現の source をそのまま使うので、規則はここだけにある。
export const WORD_PATTERN_SOURCE = "[\\p{L}\\p{N}]+(?:['’\\-][\\p{L}\\p{N}]+)*";

/// 英文の語数。句読点や記号だけのかたまりは数えない。
export function countWords(text: string): number {
  return (text.match(new RegExp(WORD_PATTERN_SOURCE, "gu")) ?? []).length;
}

/// タブ名の整形（改行は空白に潰し、前後の空白を落とし、上限で切る）。
/// 空文字も許す（そのときタブには「ページ N」を出す）。
export function sanitizePageName(raw: string): string {
  return raw.replace(/[\r\n]+/g, " ").replace(/\s+/g, " ").trim().slice(0, PAGE_NAME_MAX_LENGTH);
}

/// タブに出す表示名。名前が空なら並び順から「ページ N」を作る。
export function pageDisplayName(name: string, position: number): string {
  return name.trim() || `ページ ${position}`;
}
