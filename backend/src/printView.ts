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

/// 文字起こし英文（および同形式の平文の訳文）を印刷用ページの本文 HTML
/// （`<p>…</p>` の並び）に変換する。段落整形導入前の旧レコード
/// （単一改行のみ・改行なし長文）にも対応するため formatTranscriptParagraphs を
/// 再適用してから空行区切りで段落化する。
export function transcriptParagraphsHtml(text: string): string {
  return formatTranscriptParagraphs(text)
    .split("\n\n")
    .filter((paragraph) => paragraph.length > 0)
    .map((paragraph) => `<p>${escapeHtml(paragraph)}</p>`)
    .join("\n");
}

export interface PrintPage {
  /// html の lang 属性（英文なら "en"、訳文なら target_language）
  lang: string;
  /// 見出し兼 <title>。エスケープはこちらで行う
  title: string;
  /// 見出し下の補足行（ID・日時など）。エスケープはこちらで行う
  meta: string;
  /// 本文 HTML（呼び出し側でエスケープ/Markdown レンダリング済みのものを渡す）
  bodyHtml: string;
  /// 画面表示時のみのツールバーの戻り先
  backHref: string;
  backLabel?: string;
}

/// 印刷用ページ全体の HTML を組む。紙に印刷して読む用途のため、管理画面の
/// ダークテーマ・サイドバーは使わず白地・serif・広め行間の単独ページとして描画する。
/// ツールバー（戻るリンク・印刷ボタン）は @media print で消える。
/// 本文が Markdown 由来（Photo OCR / Document）の場合に備え、見出し・箇条書き等の
/// スタイルも用意する。
export function renderPrintPageHtml(page: PrintPage): string {
  return `<!DOCTYPE html>
<html lang="${escapeHtml(page.lang)}">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${escapeHtml(page.title)}</title>
  <style>
    :root { color-scheme: light; }
    body { margin: 0; background: #fff; color: #111; }
    .toolbar {
      display: flex; align-items: center; gap: 16px; padding: 10px 24px;
      background: #F3F4F6; border-bottom: 1px solid #D1D5DB;
      font-family: -apple-system, BlinkMacSystemFont, "Hiragino Sans", "Segoe UI", sans-serif; font-size: 13px;
    }
    .toolbar a { color: #1F6FEB; text-decoration: none; }
    .toolbar a:hover { text-decoration: underline; }
    .toolbar button {
      font: inherit; font-weight: 600; padding: 5px 16px; border-radius: 6px; cursor: pointer;
      background: #1F6FEB; color: #fff; border: none;
    }
    article {
      max-width: 42em; margin: 0 auto; padding: 32px 32px 64px;
      font-family: Georgia, "Hiragino Mincho ProN", "Yu Mincho", "Times New Roman", serif;
    }
    article > h1 { font-size: 22px; font-weight: 700; margin: 0 0 4px; }
    .meta {
      font-family: -apple-system, BlinkMacSystemFont, "Hiragino Sans", "Segoe UI", sans-serif;
      font-size: 12px; color: #6B7280; margin: 0 0 28px;
    }
    .body p, .body li { font-size: 16px; line-height: 1.9; }
    .body p { margin: 0 0 1.1em; text-align: justify; }
    .body h1, .body h2, .body h3 { font-weight: 700; margin: 1.2em 0 0.4em; }
    .body h1 { font-size: 19px; }
    .body h2 { font-size: 17px; }
    .body h3 { font-size: 16px; }
    .body ul, .body ol { margin: 0 0 1.1em; padding-left: 1.6em; }
    .body blockquote { margin: 0 0 1.1em; padding-left: 1em; border-left: 3px solid #D1D5DB; color: #374151; }
    .body hr { border: none; border-top: 1px solid #D1D5DB; margin: 1.5em 0; }
    .body code { font-family: ui-monospace, "SF Mono", Menlo, Consolas, monospace; font-size: 0.9em; }
    .no-text { color: #6B7280; }
    /* ページ番号はページドメディア（印刷/PDF）にのみ描画され、画面には出ない。
       マージンボックスは Chrome 131+ 対応。未対応ブラウザでは番号が出ないだけ。 */
    @page {
      margin: 20mm;
      @bottom-center {
        content: counter(page) " / " counter(pages);
        font-family: Georgia, "Hiragino Mincho ProN", "Yu Mincho", "Times New Roman", serif;
        font-size: 10pt;
        color: #6B7280;
      }
    }
    @media print {
      .toolbar { display: none; }
      article { max-width: none; padding: 0; }
      article > h1 { font-size: 16pt; }
      .body p, .body li { font-size: 12pt; }
      .body h1 { font-size: 14pt; }
      .body h2 { font-size: 13pt; }
      .body h3 { font-size: 12.5pt; }
    }
  </style>
</head>
<body>
  <div class="toolbar">
    <a href="${escapeHtml(page.backHref)}">${escapeHtml(page.backLabel ?? "← 一覧に戻る")}</a>
    <button type="button" onclick="window.print()">印刷</button>
  </div>
  <article>
    <h1>${escapeHtml(page.title)}</h1>
    <div class="meta">${escapeHtml(page.meta)}</div>
    <section class="body">
${page.bodyHtml}
    </section>
  </article>
</body>
</html>`;
}
