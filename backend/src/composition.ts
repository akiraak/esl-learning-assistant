// 作文（compositions）まわりの、DB にも HTTP にも依存しない定数・整形。
// admin.ts は db.ts を読み込むためテストから import できないので、
// 純粋な部分はここに置いて backend/test から直接検証する（compositionView.ts と同じ方針）。

/// 本文（英文・意図）1 つあたりの上限文字数。保存・綴り検査の受け口で共通に使う。
export const WRITING_TEXT_MAX_LENGTH = 5000;

/// 作文を新規作成するときの解説言語（現状は日本語固定）。
export const DEFAULT_EXPLANATION_LANGUAGE = "ja";
