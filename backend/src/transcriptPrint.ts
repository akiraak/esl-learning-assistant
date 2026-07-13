import { formatTranscriptParagraphs } from "./transcribe";

// admin.ts の escapeHtml と同等だが、こちらは副作用のないモジュールに置いて
// 単体テストから import できるようにする（admin.ts は db.ts を読み込むため不可）。
function escapeHtml(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

/// 文字起こし英文を印刷用ページの本文 HTML（`<p>…</p>` の並び）に変換する。
/// 段落整形導入前の旧レコード（単一改行のみ・改行なし長文）にも対応するため
/// formatTranscriptParagraphs を再適用してから空行区切りで段落化する。
export function transcriptParagraphsHtml(text: string): string {
  return formatTranscriptParagraphs(text)
    .split("\n\n")
    .filter((paragraph) => paragraph.length > 0)
    .map((paragraph) => `<p>${escapeHtml(paragraph)}</p>`)
    .join("\n");
}
