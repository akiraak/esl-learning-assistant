import path from "path";
import { Router } from "express";
import { marked } from "marked";
import { getRequestLog, listRecentRequestLogs, RequestLogRow } from "./db";
import { config } from "./config";

export const adminRouter = Router();

const PAGE_STYLE = `
  body { font-family: sans-serif; margin: 24px; }
  a { color: #06c; }
  table { border-collapse: collapse; width: 100%; }
  th, td { border: 1px solid #ccc; padding: 8px; font-size: 13px; vertical-align: top; }
  th { background: #f0f0f0; text-align: left; }
  tr.log-row:hover { background: #f7fbff; }
  .status-success { color: #2a7; }
  .status-error { color: #c33; }
`;

function escapeHtml(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

/// Markdown由来の生HTMLタグ注入を防ぐため、パース前に `&`/`<`/`>` のみエスケープする
/// （Markdownの見出し・箇条書き・強調記法は `"` を使わないため対象外）。
function renderMarkdown(value: string | null): string {
  if (!value) return "";
  const escaped = value.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
  return marked.parse(escaped, { async: false, breaks: true }) as string;
}

function renderPage(title: string, extraStyle: string, body: string): string {
  return `
    <!DOCTYPE html>
    <html lang="ja">
    <head>
      <meta charset="utf-8">
      <title>${escapeHtml(title)}</title>
      <style>
        ${PAGE_STYLE}
        ${extraStyle}
      </style>
    </head>
    <body>${body}</body>
    </html>
  `;
}

function statusLabel(log: RequestLogRow): string {
  const cls = log.status === "success" ? "status-success" : "status-error";
  return `<span class="${cls}">${escapeHtml(log.status)}</span>`;
}

// OCRモデルと翻訳モデルが同じ場合は1回の統合呼び出しにまとめており、
// 翻訳分のトークン・コストは0のままocr側に計上される。一覧・詳細で
// 「翻訳が0トークンで済んだ」ように誤解されないよう表示を分ける。
function isCombinedCall(log: RequestLogRow): boolean {
  return log.translate_model === log.ocr_model && log.translate_input_tokens === 0 && log.translate_output_tokens === 0;
}

function translateSummary(log: RequestLogRow): string {
  if (!log.translate_model) return "(なし)";
  if (isCombinedCall(log)) return "OCR呼び出しに統合（追加コストなし）";
  return `${escapeHtml(log.translate_model)} (in:${log.translate_input_tokens} / out:${log.translate_output_tokens})`;
}

adminRouter.get("/", (_req, res) => {
  const logs = listRecentRequestLogs(100);

  const rows = logs
    .map((log) => {
      const thumbnail = log.image_filename
        ? `<img src="/admin/logs/${log.id}/image" alt="photo" style="max-width:80px;max-height:80px;">`
        : "(なし)";
      return `
        <tr class="log-row">
          <td>${log.id}</td>
          <td>${escapeHtml(log.created_at)}</td>
          <td>${thumbnail}</td>
          <td>
            OCR: ${escapeHtml(log.ocr_model)} (in:${log.ocr_input_tokens} / out:${log.ocr_output_tokens})<br>
            翻訳: ${translateSummary(log)}
          </td>
          <td>
            OCR: $${log.ocr_cost_usd.toFixed(5)}<br>
            翻訳: $${log.translate_cost_usd.toFixed(5)}<br>
            合計: $${log.cost_usd.toFixed(5)}
          </td>
          <td>${statusLabel(log)}${log.error_message ? `<br>${escapeHtml(log.error_message)}` : ""}</td>
          <td>${log.latency_ms}ms</td>
          <td><a href="/admin/logs/${log.id}">詳細を見る →</a></td>
        </tr>
      `;
    })
    .join("\n");

  res.type("html").send(
    renderPage(
      "ESL Learning Assistant - 通信ログ",
      "",
      `
        <h1>Claude API 通信ログ</h1>
        <p>直近${logs.length}件</p>
        <table>
          <thead>
            <tr>
              <th>ID</th><th>日時</th><th>画像</th>
              <th>モデル/トークン数</th><th>コスト</th><th>状態</th><th>処理時間</th><th></th>
            </tr>
          </thead>
          <tbody>${rows}</tbody>
        </table>
      `
    )
  );
});

adminRouter.get("/logs/:id", (req, res) => {
  const id = Number(req.params.id);
  const log = getRequestLog(id);
  if (!log) {
    res.status(404).type("html").send(renderPage("ログが見つかりません", "", "<p>指定されたログは存在しません。</p><p><a href=\"/admin\">← 一覧に戻る</a></p>"));
    return;
  }

  const prev = getRequestLog(id + 1); // 新しいログ
  const next = getRequestLog(id - 1); // 古いログ

  const imageBlock = log.image_filename
    ? `<a href="/admin/logs/${log.id}/image" target="_blank"><img src="/admin/logs/${log.id}/image" alt="photo" class="detail-image"></a>`
    : "<p>(画像なし)</p>";

  const body = `
    <p><a href="/admin">← 一覧に戻る</a></p>
    <h1>ログ #${log.id}</h1>
    <table class="meta-table">
      <tr><th>日時</th><td>${escapeHtml(log.created_at)}</td></tr>
      <tr><th>翻訳先言語</th><td>${escapeHtml(log.target_language)}</td></tr>
      <tr><th>OCRモデル</th><td>${escapeHtml(log.ocr_model)}（in: ${log.ocr_input_tokens} / out: ${log.ocr_output_tokens}）</td></tr>
      <tr><th>翻訳モデル</th><td>${translateSummary(log)}</td></tr>
      <tr><th>コスト</th><td>OCR: $${log.ocr_cost_usd.toFixed(5)} / 翻訳: $${log.translate_cost_usd.toFixed(5)} / 合計: $${log.cost_usd.toFixed(5)}</td></tr>
      <tr><th>状態</th><td>${statusLabel(log)}${log.error_message ? `<br>${escapeHtml(log.error_message)}` : ""}</td></tr>
      <tr><th>処理時間</th><td>${log.latency_ms}ms</td></tr>
    </table>

    <div class="detail-columns">
      <div class="detail-image-col">
        <h2>画像</h2>
        ${imageBlock}
      </div>
      <div class="detail-text-col">
        <h2>OCR結果</h2>
        <div class="markdown-block">${renderMarkdown(log.ocr_text)}</div>
        <h2>翻訳結果（${escapeHtml(log.target_language)}）</h2>
        <div class="markdown-block">${renderMarkdown(log.translated_text)}</div>
      </div>
    </div>

    <p class="nav-links">
      ${prev ? `<a href="/admin/logs/${prev.id}">← 新しいログ (#${prev.id})</a>` : "<span>(これが最新)</span>"}
      &nbsp;|&nbsp;
      ${next ? `<a href="/admin/logs/${next.id}">古いログ (#${next.id}) →</a>` : "<span>(これが最古)</span>"}
    </p>
  `;

  res.type("html").send(
    renderPage(
      `ログ #${log.id} - ESL Learning Assistant`,
      `
        .meta-table { border-collapse: collapse; margin: 12px 0 24px; }
        .meta-table th, .meta-table td { border: 1px solid #ccc; padding: 6px 12px; font-size: 13px; text-align: left; }
        .meta-table th { background: #f0f0f0; }
        .detail-columns { display: flex; gap: 32px; flex-wrap: wrap; align-items: flex-start; }
        .detail-image-col { flex: 0 0 auto; }
        .detail-image { max-width: 480px; max-height: 640px; border: 1px solid #ccc; }
        .detail-text-col { flex: 1 1 480px; min-width: 320px; }
        .markdown-block {
          font-size: 16px;
          line-height: 1.7;
          border: 1px solid #ddd;
          border-radius: 6px;
          padding: 16px 20px;
          margin-bottom: 24px;
          background: #fafafa;
        }
        .markdown-block h1, .markdown-block h2, .markdown-block h3 { margin: 0.6em 0 0.3em; }
        .markdown-block p { margin: 0.6em 0; }
        .markdown-block ul, .markdown-block ol { margin: 0.3em 0; padding-left: 1.6em; }
        .markdown-block code { background: #eee; padding: 0 4px; border-radius: 3px; }
        .nav-links { margin-top: 16px; }
      `,
      body
    )
  );
});

adminRouter.get("/logs/:id/image", (req, res) => {
  const id = Number(req.params.id);
  const log = getRequestLog(id);
  if (!log?.image_filename) {
    res.status(404).end();
    return;
  }
  res.sendFile(path.join(config.imagesDir, log.image_filename));
});
