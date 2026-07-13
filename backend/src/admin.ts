import path from "path";
import crypto from "crypto";
import { Router, type Response } from "express";
import { marked } from "marked";
import fs from "fs";
import {
  countQuizQuestions,
  deleteAllStoredNormalizations,
  deleteDocumentLog,
  deleteQuizQuestions,
  deleteStoredNormalization,
  deleteStoredWord,
  deleteTranscriptionLog,
  deleteTtsAudio,
  deleteWordIllustration,
  DocumentLogRow,
  getAudioTitlesByFilename,
  getDocumentLog,
  getDocumentTitlesByFilename,
  getPricingState,
  getRequestLog,
  getStoredNormalizationById,
  getStoredWord,
  getStoredWordById,
  getTranscriptionLog,
  getTtsAudioByHash,
  getTtsAudioById,
  getUsageCostReport,
  getWordIllustrationById,
  getWordInfoLog,
  getWordNormalizeLog,
  getWritingFeedbackLog,
  insertWordInfoLog,
  listIllustratedWords,
  listQuizQuestions,
  listQuizQuestionSummaries,
  listRecentDocumentLogs,
  listRecentRequestLogs,
  listRecentSystemLogs,
  listRecentTranscriptionLogs,
  listRecentWordInfoLogs,
  listRecentWordNormalizeLogs,
  listRecentWritingFeedbackLogs,
  listStoredNormalizations,
  listStoredWords,
  listStoredWordTexts,
  listTtsAudio,
  listWordIllustrations,
  replaceQuizQuestions,
  RequestLogRow,
  StoredWordRow,
  TranscriptionLogRow,
  upsertStoredWord,
  upsertWordIllustration,
  USAGE_APPROX_FEATURES,
  type UsageFeature,
  WordInfoLogRow,
  WordNormalizeLogRow,
  WritingFeedbackLogRow,
} from "./db";
import { config } from "./config";
import { generateWordInfo, type WordInfo } from "./wordInfo";
import { type WritingFeedback } from "./writingFeedback";
import { generateQuizQuestions, type QuizQuestion } from "./quizQuestions";
import { generateIllustration, ILLUSTRATION_MODEL } from "./illustration";
import { DEFAULT_IMAGE_PRICING, DEFAULT_PRICING, DEFAULT_TTS_PRICING, estimateCostUsd, getCurrentPricing, providerLabel, type Provider } from "./pricing";
import { fetchAndApplyPricing, fetchAndApplyTtsPricing } from "./pricingSync";
import { logger } from "./logger";
import { renderPrintPageHtml, transcriptParagraphsHtml } from "./printView";
import {
  pregenerateQuizAudio,
  QUIZ_TTS_MODEL,
  regenerateWordReadingAudio,
  getWordReadingAudioRow,
} from "./ttsStore";

export const adminRouter = Router();

// ダーク基調 + 左サイドバーの共通テーマ。配色トークン:
//   地 #0C1116 / パネル #111820 / 枠線 #1F2A35 / 行区切り #18212C
//   文字 #E6EDF3 / 補助 #8B98A5 / 弱 #66737F / アクセント #38BDF8
//   success #3FB950 / error #F85149 / warn #D29922
const PAGE_STYLE = `
  :root { color-scheme: dark; }
  * { box-sizing: border-box; }
  body {
    margin: 0; background: #0C1116; color: #E6EDF3; font-size: 14px;
    font-family: -apple-system, BlinkMacSystemFont, "Hiragino Sans", "Segoe UI", sans-serif;
  }
  a { color: #38BDF8; text-decoration: none; }
  a:hover { text-decoration: underline; }
  .layout { display: flex; min-height: 100vh; }
  .sidebar {
    flex: 0 0 200px; background: #0E141B; border-right: 1px solid #1F2A35;
    padding: 18px 0; display: flex; flex-direction: column;
    position: sticky; top: 0; height: 100vh;
  }
  .sidebar .brand { color: #fff; font-weight: 700; font-size: 14px; padding: 4px 20px 18px; }
  .sidebar .brand small { display: block; font-weight: 400; font-size: 10px; color: #66737F; letter-spacing: 0.12em; margin-top: 2px; }
  .sidebar nav { display: flex; flex-direction: column; gap: 2px; }
  .sidebar nav a { color: #8B98A5; font-size: 13px; padding: 9px 20px; border-left: 3px solid transparent; }
  .sidebar nav a:hover { color: #E6EDF3; background: rgba(255,255,255,0.03); text-decoration: none; }
  .sidebar nav a.active { color: #fff; background: rgba(56,189,248,0.12); border-left-color: #38BDF8; font-weight: 600; }
  .sidebar .foot { margin-top: auto; padding: 16px 20px 4px; font-size: 11px; color: #66737F; }
  main { flex: 1; padding: 24px 28px 48px; min-width: 0; }
  h1 { font-size: 19px; margin: 0 0 4px; font-weight: 600; }
  h2 { font-size: 15px; margin: 24px 0 10px; }
  .page-sub { color: #8B98A5; font-size: 12px; margin: 0 0 18px; }
  .mono { font-family: ui-monospace, "SF Mono", Menlo, Consolas, monospace; }
  .dim { color: #8B98A5; }
  .faint { color: #66737F; }
  .ok-text { color: #3FB950; }
  .stats { display: grid; grid-template-columns: repeat(auto-fit, minmax(150px, 1fr)); gap: 14px; margin: 0 0 18px; max-width: 980px; }
  .stat { background: #111820; border: 1px solid #1F2A35; border-radius: 10px; padding: 13px 16px; }
  .stat .lbl { font-size: 11px; letter-spacing: 0.08em; color: #8B98A5; font-weight: 600; }
  .stat .val { font-size: 24px; font-weight: 700; font-variant-numeric: tabular-nums; margin-top: 2px; }
  .stat .val small { font-size: 12px; font-weight: 500; color: #8B98A5; margin-left: 2px; }
  .stat.alert .val { color: #F85149; }
  .card { background: #111820; border: 1px solid #1F2A35; border-radius: 10px; overflow-x: auto; }
  table { border-collapse: collapse; width: 100%; font-size: 12.5px; }
  th {
    text-align: left; font-size: 11px; letter-spacing: 0.08em; color: #8B98A5; font-weight: 600;
    padding: 9px 12px; border-bottom: 1px solid #1F2A35; background: #0E141B; white-space: nowrap;
  }
  td { padding: 10px 12px; border-bottom: 1px solid #18212C; vertical-align: top; font-variant-numeric: tabular-nums; }
  td a { white-space: nowrap; }
  td.mono { white-space: nowrap; }
  tbody tr:last-child td { border-bottom: none; }
  tr.log-row:hover { background: #141D28; }
  .pill {
    display: inline-flex; align-items: center; gap: 6px; font-size: 11.5px; font-weight: 600;
    padding: 2px 9px; border-radius: 4px; white-space: nowrap;
    font-family: ui-monospace, "SF Mono", Menlo, Consolas, monospace;
  }
  .status-success { color: #3FB950; background: rgba(63,185,80,0.12); border: 1px solid rgba(63,185,80,0.35); }
  .status-error { color: #F85149; background: rgba(248,81,73,0.12); border: 1px solid rgba(248,81,73,0.35); }
  .err-note { font-size: 11px; color: #F85149; margin-top: 4px; max-width: 420px; word-break: break-all; }
  .btn { font: inherit; font-size: 12.5px; font-weight: 600; padding: 6px 15px; border-radius: 6px; cursor: pointer; border: 1px solid transparent; }
  .btn-primary { background: #1F6FEB; color: #fff; }
  .btn-danger { background: transparent; color: #F85149; border-color: rgba(248,81,73,0.45); }
  img.thumb { border: 1px solid #2A3644; border-radius: 4px; }
  .meta-table { border-collapse: collapse; margin: 12px 0 24px; width: auto; }
  .meta-table th, .meta-table td { border: 1px solid #1F2A35; padding: 6px 12px; font-size: 12.5px; text-align: left; }
  .meta-table th { background: #0E141B; white-space: nowrap; }
  .markdown-block {
    font-size: 14px; line-height: 1.7; border: 1px solid #1F2A35; border-radius: 8px;
    padding: 16px 20px; margin-bottom: 24px; background: #111820;
  }
  .markdown-block h1, .markdown-block h2, .markdown-block h3 { margin: 0.6em 0 0.3em; font-size: 1.1em; }
  .markdown-block p { margin: 0.6em 0; }
  .markdown-block ul, .markdown-block ol { margin: 0.3em 0; padding-left: 1.6em; }
  .markdown-block code { background: #1B2632; padding: 0 4px; border-radius: 3px; }
  pre { background: #0E141B; border: 1px solid #1F2A35; padding: 12px; border-radius: 8px; overflow-x: auto; }
  .nav-links { margin-top: 16px; }
`;

// DBのタイムスタンプはUTCのISO文字列。管理画面ではシアトル時刻（DST自動切替）で表示する。
const SEATTLE_TZ = "America/Los_Angeles";
const seattleDateTime = new Intl.DateTimeFormat("sv-SE", {
  timeZone: SEATTLE_TZ,
  year: "numeric",
  month: "2-digit",
  day: "2-digit",
  hour: "2-digit",
  minute: "2-digit",
  second: "2-digit",
  hour12: false,
});
const seattleZoneName = new Intl.DateTimeFormat("en-US", { timeZone: SEATTLE_TZ, timeZoneName: "short" });

function formatSeattleTime(isoUtc: string): string {
  const date = new Date(isoUtc);
  if (Number.isNaN(date.getTime())) return isoUtc;
  const zone = seattleZoneName.formatToParts(date).find((p) => p.type === "timeZoneName")?.value;
  return `${seattleDateTime.format(date)}${zone ? ` ${zone}` : ""}`;
}

function escapeHtml(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

/// 一覧表示用に改行を潰して指定文字数で切り詰める（超過時は末尾に…）
function truncate(value: string, max: number): string {
  const oneLine = value.replace(/\s+/g, " ").trim();
  return oneLine.length > max ? `${oneLine.slice(0, max)}…` : oneLine;
}

/// Markdown由来の生HTMLタグ注入を防ぐため、パース前に `&`/`<`/`>` のみエスケープする
/// （Markdownの見出し・箇条書き・強調記法は `"` を使わないため対象外）。
function renderMarkdown(value: string | null): string {
  if (!value) return "";
  const escaped = value.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
  return marked.parse(escaped, { async: false, breaks: true }) as string;
}

type NavSection = "ocr" | "transcriptions" | "documents" | "word-info" | "word-normalize" | "word-normalizations" | "writing-feedback" | "words" | "quiz-questions" | "tts" | "illustrations" | "content-files" | "usage" | "pricing" | "logs";

const NAV_ITEMS: Array<[NavSection, string, string]> = [
  ["ocr", "/admin", "OCR・翻訳ログ"],
  ["transcriptions", "/admin/transcriptions", "音声文字起こしログ"],
  ["documents", "/admin/documents", "ドキュメント抽出ログ"],
  ["word-info", "/admin/word-info", "単語情報ログ"],
  ["word-normalize", "/admin/word-normalize", "単語正規化ログ"],
  ["word-normalizations", "/admin/word-normalizations", "単語正規化キャッシュ"],
  ["writing-feedback", "/admin/writing-feedback", "作文添削ログ"],
  ["words", "/admin/words", "単語一覧"],
  ["quiz-questions", "/admin/quiz-questions", "単語クイズ"],
  ["tts", "/admin/tts", "TTS一覧"],
  ["illustrations", "/admin/illustrations", "単語イラスト"],
  ["content-files", "/admin/content-files", "コンテンツファイル"],
  ["usage", "/admin/usage", "利用料金"],
  ["pricing", "/admin/pricing", "AI料金（単価）"],
  ["logs", "/admin/system-logs", "システムログ"],
];

function sidebar(active?: NavSection): string {
  const links = NAV_ITEMS.map(
    ([key, href, label]) => `<a href="${href}"${key === active ? ' class="active"' : ""}>${label}</a>`
  ).join("\n");
  return `
    <aside class="sidebar">
      <div class="brand">ESL Assistant<small>ADMIN CONSOLE</small></div>
      <nav>${links}</nav>
      <div class="foot">${SEATTLE_TZ}</div>
    </aside>
  `;
}

function renderPage(title: string, extraStyle: string, body: string, active?: NavSection): string {
  return `
    <!DOCTYPE html>
    <html lang="ja">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>${escapeHtml(title)}</title>
      <style>
        ${PAGE_STYLE}
        ${extraStyle}
      </style>
    </head>
    <body>
      <div class="layout">
        ${sidebar(active)}
        <main>${body}</main>
      </div>
    </body>
    </html>
  `;
}

function statusLabel(log: { status: string }): string {
  const ok = log.status === "success";
  return `<span class="pill ${ok ? "status-success" : "status-error"}">${ok ? "✓" : "✗"} ${escapeHtml(log.status)}</span>`;
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

  const totalCostUsd = logs.reduce((sum, log) => sum + log.cost_usd, 0);
  const errorCount = logs.filter((log) => log.status !== "success").length;
  const avgLatencySec = logs.length ? logs.reduce((sum, log) => sum + log.latency_ms, 0) / logs.length / 1000 : 0;

  const rows = logs
    .map((log) => {
      const thumbnail = log.image_filename
        ? `<img class="thumb" src="/admin/logs/${log.id}/image" alt="photo" style="max-width:80px;max-height:80px;">`
        : `<span class="faint">(なし)</span>`;
      return `
        <tr class="log-row">
          <td class="mono dim">#${log.id}</td>
          <td class="mono dim">${escapeHtml(formatSeattleTime(log.created_at))}</td>
          <td>${thumbnail}</td>
          <td>
            OCR: <strong>${escapeHtml(log.ocr_model)}</strong> <span class="dim">(in:${log.ocr_input_tokens} / out:${log.ocr_output_tokens})</span><br>
            翻訳: ${translateSummary(log)}
          </td>
          <td class="mono">
            <strong>$${log.cost_usd.toFixed(5)}</strong><br>
            <span class="faint">OCR $${log.ocr_cost_usd.toFixed(5)} / 翻訳 $${log.translate_cost_usd.toFixed(5)}</span>
          </td>
          <td>${statusLabel(log)}${log.error_message ? `<div class="err-note">${escapeHtml(log.error_message)}</div>` : ""}</td>
          <td class="mono dim">${log.latency_ms}ms</td>
          <td><a href="/admin/logs/${log.id}">詳細 →</a></td>
        </tr>
      `;
    })
    .join("\n");

  res.type("html").send(
    renderPage(
      "ESL Assistant - 通信ログ",
      "",
      `
        <h1>Claude API 通信ログ</h1>
        <p class="page-sub">直近${logs.length}件のOCR・翻訳リクエスト</p>
        <div class="stats">
          <div class="stat"><div class="lbl">直近件数</div><div class="val">${logs.length}<small>件</small></div></div>
          <div class="stat"><div class="lbl">コスト合計</div><div class="val">$${totalCostUsd.toFixed(2)}</div></div>
          <div class="stat${errorCount > 0 ? " alert" : ""}"><div class="lbl">エラー</div><div class="val">${errorCount}<small>件</small></div></div>
          <div class="stat"><div class="lbl">平均処理時間</div><div class="val">${avgLatencySec.toFixed(1)}<small>s</small></div></div>
        </div>
        <div class="card">
          <table>
            <thead>
              <tr>
                <th>ID</th><th>日時</th><th>画像</th>
                <th>モデル / トークン</th><th>コスト</th><th>状態</th><th>処理時間</th><th></th>
              </tr>
            </thead>
            <tbody>${rows}</tbody>
          </table>
        </div>
      `,
      "ocr"
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
      <tr><th>日時</th><td>${escapeHtml(formatSeattleTime(log.created_at))}</td></tr>
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
        <h2>OCR結果 ${log.ocr_text ? `<a class="print-link" href="/admin/logs/${log.id}/text" target="_blank">印刷用表示</a>` : ""}</h2>
        <div class="markdown-block">${renderMarkdown(log.ocr_text)}</div>
        <h2>翻訳結果（${escapeHtml(log.target_language)}） ${log.translated_text ? `<a class="print-link" href="/admin/logs/${log.id}/translation" target="_blank">印刷用表示</a>` : ""}</h2>
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
      `ログ #${log.id} - ESL Assistant`,
      `
        .detail-columns { display: flex; gap: 32px; flex-wrap: wrap; align-items: flex-start; }
        .detail-image-col { flex: 0 0 auto; }
        .detail-image { max-width: 480px; max-height: 640px; border: 1px solid #2A3644; border-radius: 4px; }
        .detail-text-col { flex: 1 1 480px; min-width: 320px; }
        .detail-text-col .markdown-block { font-size: 16px; }
        .print-link { font-size: 12px; font-weight: 400; margin-left: 6px; }
      `,
      body,
      "ocr"
    )
  );
});

// 写真OCRの英文・訳文の印刷用表示（docs/plans/admin-print-views-photo-document-translation.md）。
// OCR結果は Markdown（詳細ページと同じ renderMarkdown）で組む。
function sendPhotoPrintPage(res: Response, id: number, kind: "text" | "translation"): void {
  const log = getRequestLog(id);
  if (!log) {
    res.status(404).type("html").send(
      renderPage("ログが見つかりません", "", '<p>指定されたログは存在しません。</p><p><a href="/admin">← 一覧に戻る</a></p>')
    );
    return;
  }
  const isTranslation = kind === "translation";
  const text = isTranslation ? log.translated_text : log.ocr_text;
  res.type("html").send(
    renderPrintPageHtml({
      lang: isTranslation ? log.target_language : "en",
      title: `Photo OCR #${log.id}`,
      meta: `#${log.id} ・ ${formatSeattleTime(log.created_at)}${isTranslation ? ` ・ 訳 (${log.target_language})` : ""}`,
      bodyHtml: text ? renderMarkdown(text) : `<p class="no-text">(このログには${isTranslation ? "訳文" : "英文"}がありません)</p>`,
      backHref: `/admin/logs/${log.id}`,
      backLabel: "← 詳細に戻る",
    })
  );
}

adminRouter.get("/logs/:id/text", (req, res) => {
  sendPhotoPrintPage(res, Number(req.params.id), "text");
});

adminRouter.get("/logs/:id/translation", (req, res) => {
  sendPhotoPrintPage(res, Number(req.params.id), "translation");
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

adminRouter.get("/word-info", (_req, res) => {
  const logs = listRecentWordInfoLogs(100);

  const totalCostUsd = logs.reduce((sum, log) => sum + log.cost_usd, 0);
  const cacheHits = logs.filter((log) => log.cache_hit).length;
  const errorCount = logs.filter((log) => log.status !== "success").length;

  const rows = logs
    .map(
      (log) => `
        <tr class="log-row">
          <td class="mono dim">#${log.id}</td>
          <td class="mono dim">${escapeHtml(formatSeattleTime(log.created_at))}</td>
          <td><strong>${escapeHtml(log.word)}</strong>${
            log.user_translation ? `<br><span class="dim">${escapeHtml(log.user_translation)}</span>` : ""
          }</td>
          <td>${escapeHtml(log.target_language)}</td>
          <td>${log.context ? "あり" : `<span class="faint">なし</span>`}</td>
          <td>${log.cache_hit ? '<span class="ok-text">キャッシュ返却</span><br>' : ""}<strong>${escapeHtml(log.model)}</strong> <span class="dim">(in:${log.input_tokens} / out:${log.output_tokens})</span></td>
          <td class="mono">$${log.cost_usd.toFixed(5)}</td>
          <td>${statusLabel(log)}${log.error_message ? `<div class="err-note">${escapeHtml(log.error_message)}</div>` : ""}</td>
          <td class="mono dim">${log.latency_ms}ms</td>
          <td><a href="/admin/word-info/${log.id}">詳細 →</a></td>
        </tr>
      `
    )
    .join("\n");

  res.type("html").send(
    renderPage(
      "ESL Assistant - 単語情報ログ",
      "",
      `
        <h1>単語情報生成ログ</h1>
        <p class="page-sub">直近${logs.length}件の単語情報リクエスト</p>
        <div class="stats">
          <div class="stat"><div class="lbl">直近件数</div><div class="val">${logs.length}<small>件</small></div></div>
          <div class="stat"><div class="lbl">コスト合計</div><div class="val">$${totalCostUsd.toFixed(2)}</div></div>
          <div class="stat"><div class="lbl">キャッシュ返却</div><div class="val">${cacheHits}<small>件</small></div></div>
          <div class="stat${errorCount > 0 ? " alert" : ""}"><div class="lbl">エラー</div><div class="val">${errorCount}<small>件</small></div></div>
        </div>
        <div class="card">
          <table>
            <thead>
              <tr>
                <th>ID</th><th>日時</th><th>単語</th><th>母語</th><th>文脈</th>
                <th>モデル / トークン</th><th>コスト</th><th>状態</th><th>処理時間</th><th></th>
              </tr>
            </thead>
            <tbody>${rows}</tbody>
          </table>
        </div>
      `,
      "word-info"
    )
  );
});

/// word_info_json を人が読める形に整形する（パース不能ならJSONをそのまま表示）。
/// 単語情報ログ（WordInfoLogRow）と保存済み単語（StoredWordRow）の両方で使う。
function renderWordInfoBlock(row: { word_info_json: string | null }): string {
  if (!row.word_info_json) return "<p>(生成結果なし)</p>";

  let info: WordInfo;
  try {
    info = JSON.parse(row.word_info_json) as WordInfo;
  } catch {
    return `<pre>${escapeHtml(row.word_info_json)}</pre>`;
  }

  const senses = info.senses
    .map(
      (sense, i) => `
        <tr>
          <td class="dim">${i + 1}</td>
          <td>${escapeHtml(sense.partOfSpeech)}</td>
          <td>${escapeHtml(sense.meaning)}</td>
          <td>${escapeHtml(sense.englishDefinition)}</td>
          <td>${sense.note ? escapeHtml(sense.note) : ""}</td>
        </tr>
      `
    )
    .join("\n");

  const examples = info.examples
    .map((ex) => `<li>${escapeHtml(ex.english)}<br><span class="dim">${escapeHtml(ex.translation)}</span></li>`)
    .join("\n");

  const inflections = info.inflections
    .map((inf) => `${escapeHtml(inf.form)}: ${escapeHtml(inf.text)}`)
    .join(" / ");

  const optionalRow = (label: string, value: string | null) =>
    value ? `<tr><th>${label}</th><td>${escapeHtml(value)}</td></tr>` : "";

  return `
    <h2>語義</h2>
    <div class="card">
      <table>
        <thead><tr><th>#</th><th>品詞</th><th>意味</th><th>英語定義</th><th>ニュアンス</th></tr></thead>
        <tbody>${senses}</tbody>
      </table>
    </div>
    <h2>例文</h2>
    <ul>${examples}</ul>
    <h2>その他</h2>
    <table class="meta-table">
      <tr><th>発音</th><td>${escapeHtml(info.pronunciation.ipa)}${
        info.pronunciation.syllables ? ` / ${escapeHtml(info.pronunciation.syllables)}` : ""
      }</td></tr>
      ${inflections ? `<tr><th>語形変化</th><td>${inflections}</td></tr>` : ""}
      ${info.collocations.length ? `<tr><th>コロケーション</th><td>${escapeHtml(info.collocations.join(", "))}</td></tr>` : ""}
      ${info.synonyms.length ? `<tr><th>類義語</th><td>${escapeHtml(info.synonyms.join(", "))}</td></tr>` : ""}
      ${info.antonyms.length ? `<tr><th>反意語</th><td>${escapeHtml(info.antonyms.join(", "))}</td></tr>` : ""}
      ${optionalRow("使用上の注意", info.usageNote)}
      ${optionalRow("CEFR", info.cefrLevel)}
      ${optionalRow("使用域", info.register)}
      ${optionalRow("語源・記憶のヒント", info.etymology)}
      ${optionalRow("よくある間違い", info.commonMistakes)}
    </table>
    <h2>生JSON</h2>
    <details><summary>表示する</summary><pre>${escapeHtml(JSON.stringify(info, null, 2))}</pre></details>
  `;
}

adminRouter.get("/word-info/:id", (req, res) => {
  const id = Number(req.params.id);
  const log = getWordInfoLog(id);
  if (!log) {
    res
      .status(404)
      .type("html")
      .send(
        renderPage(
          "ログが見つかりません",
          "",
          '<p>指定されたログは存在しません。</p><p><a href="/admin/word-info">← 一覧に戻る</a></p>'
        )
      );
    return;
  }

  const prev = getWordInfoLog(id + 1); // 新しいログ
  const next = getWordInfoLog(id - 1); // 古いログ

  const body = `
    <p><a href="/admin/word-info">← 一覧に戻る</a></p>
    <h1>単語情報ログ #${log.id}: ${escapeHtml(log.word)}</h1>
    <table class="meta-table">
      <tr><th>日時</th><td>${escapeHtml(formatSeattleTime(log.created_at))}</td></tr>
      <tr><th>単語</th><td>${escapeHtml(log.word)}</td></tr>
      <tr><th>ユーザー訳語</th><td>${log.user_translation ? escapeHtml(log.user_translation) : "(なし)"}</td></tr>
      <tr><th>母語</th><td>${escapeHtml(log.target_language)}</td></tr>
      <tr><th>キャッシュ</th><td>${log.cache_hit ? '<span style="color:#2a7">保存済みを返却（生成なし）</span>' : "新規生成"}</td></tr>
      <tr><th>モデル</th><td>${escapeHtml(log.model)}（in: ${log.input_tokens} / out: ${log.output_tokens}）</td></tr>
      <tr><th>コスト</th><td>$${log.cost_usd.toFixed(5)}</td></tr>
      <tr><th>状態</th><td>${statusLabel(log)}${log.error_message ? `<br>${escapeHtml(log.error_message)}` : ""}</td></tr>
      <tr><th>処理時間</th><td>${log.latency_ms}ms</td></tr>
    </table>

    ${renderWordInfoBlock(log)}

    <h2>文脈（教科書本文）</h2>
    ${log.context ? `<div class="markdown-block">${renderMarkdown(log.context)}</div>` : "<p>(なし)</p>"}

    <p class="nav-links">
      ${prev ? `<a href="/admin/word-info/${prev.id}">← 新しいログ (#${prev.id})</a>` : "<span>(これが最新)</span>"}
      &nbsp;|&nbsp;
      ${next ? `<a href="/admin/word-info/${next.id}">古いログ (#${next.id}) →</a>` : "<span>(これが最古)</span>"}
    </p>
  `;

  res.type("html").send(renderPage(`単語情報ログ #${log.id} - ESL Assistant`, "", body, "word-info"));
});

// 正規化結果ステータス（canonical/inflected/...）の日本語ラベル。
const NORMALIZE_STATUS_LABELS: Record<string, string> = {
  canonical: "見出し語",
  inflected: "語形変化",
  misspelled: "綴り訂正",
  proper_noun: "固有名詞",
  phrase: "連語",
  unknown: "判定不能",
};

function normalizeStatusBadge(status: string | null): string {
  if (!status) return `<span class="faint">-</span>`;
  const label = NORMALIZE_STATUS_LABELS[status] ?? status;
  // 訂正が入る2種（inflected/misspelled）を強調、その他は控えめに表示する
  const corrected = status === "inflected" || status === "misspelled";
  return `<span class="pill ${corrected ? "status-error" : "status-success"}">${escapeHtml(label)}</span>`;
}

adminRouter.get("/word-normalize", (_req, res) => {
  const logs = listRecentWordNormalizeLogs(100);

  const totalCostUsd = logs.reduce((sum, log) => sum + log.cost_usd, 0);
  const cacheHits = logs.filter((log) => log.cache_hit).length;
  const correctedCount = logs.filter(
    (log) => log.result_status === "inflected" || log.result_status === "misspelled"
  ).length;
  const errorCount = logs.filter((log) => log.status !== "success").length;

  const rows = logs
    .map(
      (log) => `
        <tr class="log-row">
          <td class="mono dim">#${log.id}</td>
          <td class="mono dim">${escapeHtml(formatSeattleTime(log.created_at))}</td>
          <td><strong>${escapeHtml(log.input)}</strong></td>
          <td>${normalizeStatusBadge(log.result_status)}</td>
          <td>${
            log.lemma && log.lemma !== log.input
              ? `<strong class="ok-text">${escapeHtml(log.lemma)}</strong>`
              : `<span class="dim">${log.lemma ? escapeHtml(log.lemma) : "-"}</span>`
          }${log.reason ? `<br><span class="dim">${escapeHtml(log.reason)}</span>` : ""}</td>
          <td>${escapeHtml(log.target_language)}</td>
          <td>${log.cache_hit ? '<span class="ok-text">キャッシュ返却</span><br>' : ""}<strong>${escapeHtml(log.model)}</strong> <span class="dim">(in:${log.input_tokens} / out:${log.output_tokens})</span></td>
          <td class="mono">$${log.cost_usd.toFixed(5)}</td>
          <td>${statusLabel(log)}${log.error_message ? `<div class="err-note">${escapeHtml(log.error_message)}</div>` : ""}</td>
          <td class="mono dim">${log.latency_ms}ms</td>
          <td><a href="/admin/word-normalize/${log.id}">詳細 →</a></td>
        </tr>
      `
    )
    .join("\n");

  res.type("html").send(
    renderPage(
      "ESL Assistant - 単語正規化ログ",
      "",
      `
        <h1>単語正規化ログ</h1>
        <p class="page-sub">直近${logs.length}件の入力語正規化（原形化・綴り訂正）リクエスト</p>
        <div class="stats">
          <div class="stat"><div class="lbl">直近件数</div><div class="val">${logs.length}<small>件</small></div></div>
          <div class="stat"><div class="lbl">コスト合計</div><div class="val">$${totalCostUsd.toFixed(2)}</div></div>
          <div class="stat"><div class="lbl">訂正あり</div><div class="val">${correctedCount}<small>件</small></div></div>
          <div class="stat"><div class="lbl">キャッシュ返却</div><div class="val">${cacheHits}<small>件</small></div></div>
          <div class="stat${errorCount > 0 ? " alert" : ""}"><div class="lbl">エラー</div><div class="val">${errorCount}<small>件</small></div></div>
        </div>
        <div class="card">
          <table>
            <thead>
              <tr>
                <th>ID</th><th>日時</th><th>入力</th><th>判定</th><th>lemma / 理由</th><th>母語</th>
                <th>モデル / トークン</th><th>コスト</th><th>状態</th><th>処理時間</th><th></th>
              </tr>
            </thead>
            <tbody>${rows}</tbody>
          </table>
        </div>
      `,
      "word-normalize"
    )
  );
});

adminRouter.get("/word-normalize/:id", (req, res) => {
  const id = Number(req.params.id);
  const log = getWordNormalizeLog(id);
  if (!log) {
    res
      .status(404)
      .type("html")
      .send(
        renderPage(
          "ログが見つかりません",
          "",
          '<p>指定されたログは存在しません。</p><p><a href="/admin/word-normalize">← 一覧に戻る</a></p>'
        )
      );
    return;
  }

  const prev = getWordNormalizeLog(id + 1); // 新しいログ
  const next = getWordNormalizeLog(id - 1); // 古いログ

  const body = `
    <p><a href="/admin/word-normalize">← 一覧に戻る</a></p>
    <h1>単語正規化ログ #${log.id}: ${escapeHtml(log.input)}</h1>
    <table class="meta-table">
      <tr><th>日時</th><td>${escapeHtml(formatSeattleTime(log.created_at))}</td></tr>
      <tr><th>入力</th><td>${escapeHtml(log.input)}</td></tr>
      <tr><th>判定</th><td>${normalizeStatusBadge(log.result_status)}</td></tr>
      <tr><th>lemma（登録語）</th><td>${log.lemma ? escapeHtml(log.lemma) : "(なし)"}</td></tr>
      <tr><th>理由</th><td>${log.reason ? escapeHtml(log.reason) : "(なし)"}</td></tr>
      <tr><th>母語</th><td>${escapeHtml(log.target_language)}</td></tr>
      <tr><th>キャッシュ</th><td>${log.cache_hit ? '<span style="color:#2a7">保存済みを返却（生成なし）</span>' : "新規生成"}</td></tr>
      <tr><th>モデル</th><td>${escapeHtml(log.model)}（in: ${log.input_tokens} / out: ${log.output_tokens}）</td></tr>
      <tr><th>コスト</th><td>$${log.cost_usd.toFixed(5)}</td></tr>
      <tr><th>状態</th><td>${statusLabel(log)}${log.error_message ? `<br>${escapeHtml(log.error_message)}` : ""}</td></tr>
      <tr><th>処理時間</th><td>${log.latency_ms}ms</td></tr>
    </table>

    <p class="nav-links">
      ${prev ? `<a href="/admin/word-normalize/${prev.id}">← 新しいログ (#${prev.id})</a>` : "<span>(これが最新)</span>"}
      &nbsp;|&nbsp;
      ${next ? `<a href="/admin/word-normalize/${next.id}">古いログ (#${next.id}) →</a>` : "<span>(これが最古)</span>"}
    </p>
  `;

  res.type("html").send(renderPage(`単語正規化ログ #${log.id} - ESL Assistant`, "", body, "word-normalize"));
});

// 単語正規化キャッシュ（word_normalizations）そのものの閲覧・削除。
// /admin/word-normalize は通信ログ、こちらは実際にヒットするキャッシュ表を操作する。
adminRouter.get("/word-normalizations", (_req, res) => {
  const rows = listStoredNormalizations();

  const correctedCount = rows.filter(
    (row) => row.status === "inflected" || row.status === "misspelled"
  ).length;

  const tableRows = rows
    .map(
      (row) => `
        <tr class="log-row">
          <td class="mono dim">#${row.id}</td>
          <td><strong>${escapeHtml(row.input)}</strong></td>
          <td>${normalizeStatusBadge(row.status)}</td>
          <td>${
            row.lemma && row.lemma.toLowerCase() !== row.input.toLowerCase()
              ? `<strong class="ok-text">${escapeHtml(row.lemma)}</strong>`
              : `<span class="dim">${escapeHtml(row.lemma)}</span>`
          }</td>
          <td>${row.reason ? `<span class="dim">${escapeHtml(row.reason)}</span>` : "-"}</td>
          <td>${escapeHtml(row.target_language)}</td>
          <td class="dim">${escapeHtml(row.model)}</td>
          <td class="mono dim">${row.generation_count}</td>
          <td class="mono dim">${escapeHtml(formatSeattleTime(row.updated_at))}</td>
          <td>
            <form method="post" action="/admin/word-normalizations/${row.id}/delete"
                  onsubmit="return confirm('「${escapeHtml(row.input)}」の正規化キャッシュを削除します。よろしいですか？（アプリから再登録されれば作り直されます）')">
              <button type="submit" class="btn btn-danger">削除</button>
            </form>
          </td>
        </tr>
      `
    )
    .join("\n");

  res.type("html").send(
    renderPage(
      "ESL Assistant - 単語正規化キャッシュ",
      ".log-row td form { margin: 0; }",
      `
        <h1>単語正規化キャッシュ</h1>
        <p class="page-sub">入力語→lemma の正規化結果キャッシュ（<code>word_normalizations</code>）。全${rows.length}件</p>
        <div class="stats">
          <div class="stat"><div class="lbl">総件数</div><div class="val">${rows.length}<small>件</small></div></div>
          <div class="stat"><div class="lbl">訂正あり</div><div class="val">${correctedCount}<small>件</small></div></div>
        </div>
        ${
          rows.length > 0
            ? `<form method="post" action="/admin/word-normalizations/delete-all" style="margin:0 0 16px;"
                     onsubmit="return confirm('正規化キャッシュを全${rows.length}件削除します。よろしいですか？（キャッシュなので、以降アクセスされた語は新しいプロンプトで作り直されます）')">
                 <button type="submit" class="btn btn-danger">全削除（${rows.length}件）</button>
               </form>`
            : ""
        }
        <div class="card">
          <table>
            <thead>
              <tr>
                <th>ID</th><th>入力</th><th>判定</th><th>lemma</th><th>理由</th><th>母語</th>
                <th>モデル</th><th>生成回数</th><th>更新日時</th><th></th>
              </tr>
            </thead>
            <tbody>${tableRows || '<tr><td colspan="10" class="dim">キャッシュはまだありません。</td></tr>'}</tbody>
          </table>
        </div>
      `,
      "word-normalizations"
    )
  );
});

adminRouter.post("/word-normalizations/:id/delete", (req, res) => {
  const id = Number(req.params.id);
  const row = getStoredNormalizationById(id);
  if (!row) {
    res
      .status(404)
      .type("html")
      .send(
        renderPage(
          "キャッシュが見つかりません",
          "",
          '<p>指定された正規化キャッシュは存在しません。</p><p><a href="/admin/word-normalizations">← 一覧に戻る</a></p>'
        )
      );
    return;
  }
  deleteStoredNormalization(id);
  logger.info(`admin: deleted word normalization cache #${id} input="${row.input}" (${row.target_language})`);
  res.redirect("/admin/word-normalizations");
});

adminRouter.post("/word-normalizations/delete-all", (_req, res) => {
  const deleted = deleteAllStoredNormalizations();
  logger.info(`admin: deleted all word normalization cache (${deleted} rows)`);
  res.redirect("/admin/word-normalizations");
});

adminRouter.get("/writing-feedback", (_req, res) => {
  const logs = listRecentWritingFeedbackLogs(100);

  const totalCostUsd = logs.reduce((sum, log) => sum + log.cost_usd, 0);
  const errorCount = logs.filter((log) => log.status !== "success").length;

  const rows = logs
    .map(
      (log) => `
        <tr class="log-row">
          <td class="mono dim">#${log.id}</td>
          <td class="mono dim">${escapeHtml(formatSeattleTime(log.created_at))}</td>
          <td>${escapeHtml(truncate(log.english_text, 60))}<br><span class="dim">${escapeHtml(truncate(log.japanese_text, 60))}</span></td>
          <td>${escapeHtml(log.explanation_language)}</td>
          <td><strong>${escapeHtml(log.model)}</strong> <span class="dim">(in:${log.input_tokens} / out:${log.output_tokens})</span></td>
          <td class="mono">$${log.cost_usd.toFixed(5)}</td>
          <td>${statusLabel(log)}${log.error_message ? `<div class="err-note">${escapeHtml(log.error_message)}</div>` : ""}</td>
          <td class="mono dim">${log.latency_ms}ms</td>
          <td><a href="/admin/writing-feedback/${log.id}">詳細 →</a></td>
        </tr>
      `
    )
    .join("\n");

  res.type("html").send(
    renderPage(
      "ESL Assistant - 作文添削ログ",
      "",
      `
        <h1>作文添削ログ</h1>
        <p class="page-sub">直近${logs.length}件の作文添削リクエスト</p>
        <div class="stats">
          <div class="stat"><div class="lbl">直近件数</div><div class="val">${logs.length}<small>件</small></div></div>
          <div class="stat"><div class="lbl">コスト合計</div><div class="val">$${totalCostUsd.toFixed(2)}</div></div>
          <div class="stat${errorCount > 0 ? " alert" : ""}"><div class="lbl">エラー</div><div class="val">${errorCount}<small>件</small></div></div>
        </div>
        <div class="card">
          <table>
            <thead>
              <tr>
                <th>ID</th><th>日時</th><th>英文 / 意図</th><th>解説言語</th>
                <th>モデル / トークン</th><th>コスト</th><th>状態</th><th>処理時間</th><th></th>
              </tr>
            </thead>
            <tbody>${rows}</tbody>
          </table>
        </div>
      `,
      "writing-feedback"
    )
  );
});

/// feedback_json を人が読める形に整形する（パース不能ならJSONをそのまま表示）。
function renderWritingFeedbackBlock(row: { feedback_json: string | null }): string {
  if (!row.feedback_json) return "<p>(生成結果なし)</p>";

  let feedback: WritingFeedback;
  try {
    feedback = JSON.parse(row.feedback_json) as WritingFeedback;
  } catch {
    return `<pre>${escapeHtml(row.feedback_json)}</pre>`;
  }

  return `
    <h2>修正後の英文</h2>
    <div class="markdown-block">${renderMarkdown(feedback.correctedText)}</div>
    <h2>解説</h2>
    <div class="markdown-block">${renderMarkdown(feedback.explanation)}</div>
  `;
}

adminRouter.get("/writing-feedback/:id", (req, res) => {
  const id = Number(req.params.id);
  const log = getWritingFeedbackLog(id);
  if (!log) {
    res
      .status(404)
      .type("html")
      .send(
        renderPage(
          "ログが見つかりません",
          "",
          '<p>指定されたログは存在しません。</p><p><a href="/admin/writing-feedback">← 一覧に戻る</a></p>'
        )
      );
    return;
  }

  const prev = getWritingFeedbackLog(id + 1); // 新しいログ
  const next = getWritingFeedbackLog(id - 1); // 古いログ

  const body = `
    <p><a href="/admin/writing-feedback">← 一覧に戻る</a></p>
    <h1>作文添削ログ #${log.id}</h1>
    <table class="meta-table">
      <tr><th>日時</th><td>${escapeHtml(formatSeattleTime(log.created_at))}</td></tr>
      <tr><th>解説言語</th><td>${escapeHtml(log.explanation_language)}</td></tr>
      <tr><th>モデル</th><td>${escapeHtml(log.model)}（in: ${log.input_tokens} / out: ${log.output_tokens}）</td></tr>
      <tr><th>コスト</th><td>$${log.cost_usd.toFixed(5)}</td></tr>
      <tr><th>状態</th><td>${statusLabel(log)}${log.error_message ? `<br>${escapeHtml(log.error_message)}` : ""}</td></tr>
      <tr><th>処理時間</th><td>${log.latency_ms}ms</td></tr>
    </table>

    <h2>学習者が書いた英文</h2>
    <div class="markdown-block">${renderMarkdown(log.english_text)}</div>

    <h2>伝えたかった意図</h2>
    <div class="markdown-block">${renderMarkdown(log.japanese_text)}</div>

    ${renderWritingFeedbackBlock(log)}

    <p class="nav-links">
      ${prev ? `<a href="/admin/writing-feedback/${prev.id}">← 新しいログ (#${prev.id})</a>` : "<span>(これが最新)</span>"}
      &nbsp;|&nbsp;
      ${next ? `<a href="/admin/writing-feedback/${next.id}">古いログ (#${next.id}) →</a>` : "<span>(これが最古)</span>"}
    </p>
  `;

  res.type("html").send(renderPage(`作文添削ログ #${log.id} - ESL Assistant`, "", body, "writing-feedback"));
});

/// 一覧プレビュー用に先頭語義を取り出す（パース不能なら空文字）
function firstMeaningPreview(row: StoredWordRow): string {
  try {
    const info = JSON.parse(row.word_info_json) as WordInfo;
    return info.senses[0]?.meaning ?? "";
  } catch {
    return "";
  }
}

/// 単語一覧・詳細に出すクイズ問題の状態表示。
/// 0件は生成ボタン（アプリの自己修復トリガに頼らず管理画面から生成でき、失敗時はエラーが見える）、
/// 1件以上は問題数を詳細ページへのリンクで表示する
function quizStatusCell(word: string, targetLanguage: string): string {
  const count = countQuizQuestions(word, targetLanguage);
  if (count > 0) {
    return `<a href="/admin/quiz-questions/item?${quizItemQuery(word, targetLanguage)}">${count}問</a>`;
  }
  return `
    <form method="post" action="/admin/quiz-questions/regenerate?${quizItemQuery(word, targetLanguage)}"
          onsubmit="return confirm('この単語のクイズ問題を生成します。よろしいですか？')">
      <button type="submit" class="btn btn-primary">生成</button>
    </form>
  `;
}

adminRouter.get("/words", (_req, res) => {
  const words = listStoredWords();

  const rows = words
    .map(
      (row) => `
        <tr class="log-row">
          <td class="mono dim">#${row.id}</td>
          <td><strong>${escapeHtml(row.word)}</strong></td>
          <td>${escapeHtml(row.target_language)}</td>
          <td>${escapeHtml(firstMeaningPreview(row))}</td>
          <td class="dim">${escapeHtml(row.model)}</td>
          <td class="mono dim">${row.generation_count}</td>
          <td>${quizStatusCell(row.word, row.target_language)}</td>
          <td class="mono dim">${escapeHtml(formatSeattleTime(row.created_at))}</td>
          <td class="mono dim">${escapeHtml(formatSeattleTime(row.updated_at))}</td>
          <td><a href="/admin/words/${row.id}">詳細 →</a></td>
        </tr>
      `
    )
    .join("\n");

  res.type("html").send(
    renderPage(
      "ESL Assistant - 単語一覧",
      "",
      `
        <h1>保存済み単語一覧</h1>
        <p class="page-sub">全${words.length}件</p>
        <div class="card">
          <table>
            <thead>
              <tr>
                <th>ID</th><th>単語</th><th>母語</th><th>先頭語義</th>
                <th>モデル</th><th>生成回数</th><th>クイズ</th><th>作成日時</th><th>更新日時</th><th></th>
              </tr>
            </thead>
            <tbody>${rows}</tbody>
          </table>
        </div>
      `,
      "words"
    )
  );
});

const WORD_DETAIL_STYLE = `
  .action-buttons { display: flex; gap: 12px; margin: 16px 0 24px; }
`;

adminRouter.get("/words/:id", (req, res) => {
  const id = Number(req.params.id);
  const row = getStoredWordById(id);
  if (!row) {
    res
      .status(404)
      .type("html")
      .send(
        renderPage(
          "単語が見つかりません",
          "",
          '<p>指定された単語は存在しません。</p><p><a href="/admin/words">← 一覧に戻る</a></p>'
        )
      );
    return;
  }

  const readingAudio = getWordReadingAudioRow(row.word);
  const readingAudioCell = readingAudio
    ? `<audio controls preload="none" src="/admin/tts/${readingAudio.id}/audio" style="width:220px;height:32px;vertical-align:middle;"></audio>` +
      ` <span class="faint">(${escapeHtml(readingAudio.voice)} / ${escapeHtml(readingAudio.model)})</span>`
    : "<span class=\"faint\">(未生成 — アプリで発音を再生すると作成されます)</span>";

  const body = `
    <p><a href="/admin/words">← 一覧に戻る</a></p>
    <h1>単語 #${row.id}: ${escapeHtml(row.word)}</h1>
    <table class="meta-table">
      <tr><th>単語</th><td>${escapeHtml(row.word)}</td></tr>
      <tr><th>母語</th><td>${escapeHtml(row.target_language)}</td></tr>
      <tr><th>ユーザー訳語</th><td>${row.user_translation ? escapeHtml(row.user_translation) : "(なし)"}</td></tr>
      <tr><th>モデル</th><td>${escapeHtml(row.model)}</td></tr>
      <tr><th>生成回数</th><td>${row.generation_count}</td></tr>
      <tr><th>読み上げ音声</th><td>${readingAudioCell}</td></tr>
      <tr><th>クイズ問題</th><td>${quizStatusCell(row.word, row.target_language)}</td></tr>
      <tr><th>作成日時</th><td>${escapeHtml(formatSeattleTime(row.created_at))}</td></tr>
      <tr><th>更新日時</th><td>${escapeHtml(formatSeattleTime(row.updated_at))}</td></tr>
    </table>

    <div class="action-buttons">
      <form method="post" action="/admin/words/${row.id}/regenerate"
            onsubmit="return confirm('AI情報を再生成します。現在の内容は上書きされます。よろしいですか？')">
        <button type="submit" class="btn btn-primary">再生成する</button>
      </form>
      <form method="post" action="/admin/words/${row.id}/regenerate-audio"
            onsubmit="return confirm('この単語の読み上げ音声を作り直します（ボイスは再抽選）。よろしいですか？')">
        <button type="submit" class="btn">読み上げ音声を再生成</button>
      </form>
      <form method="post" action="/admin/words/${row.id}/delete"
            onsubmit="return confirm('この単語の保存データを削除します。よろしいですか？（アプリから再リクエストされれば再生成されます）')">
        <button type="submit" class="btn btn-danger">削除する</button>
      </form>
    </div>

    ${renderWordInfoBlock(row)}

    <h2>文脈（最後の生成に使用）</h2>
    ${row.context ? `<div class="markdown-block">${renderMarkdown(row.context)}</div>` : "<p>(なし)</p>"}
  `;

  res.type("html").send(renderPage(`単語 #${row.id}: ${row.word} - ESL Assistant`, WORD_DETAIL_STYLE, body, "words"));
});

adminRouter.post("/words/:id/delete", (req, res) => {
  const id = Number(req.params.id);
  const row = getStoredWordById(id);
  if (!row) {
    res.status(404).type("html").send(
      renderPage("単語が見つかりません", "", '<p>指定された単語は存在しません。</p><p><a href="/admin/words">← 一覧に戻る</a></p>')
    );
    return;
  }
  deleteStoredWord(id);
  logger.info(`admin: deleted stored word #${id} "${row.word}" (${row.target_language})`);
  res.redirect("/admin/words");
});

adminRouter.post("/words/:id/regenerate", async (req, res) => {
  const id = Number(req.params.id);
  const row = getStoredWordById(id);
  if (!row) {
    res.status(404).type("html").send(
      renderPage("単語が見つかりません", "", '<p>指定された単語は存在しません。</p><p><a href="/admin/words">← 一覧に戻る</a></p>')
    );
    return;
  }

  const startedAt = Date.now();
  logger.info(`admin: regenerate stored word #${id} "${row.word}" (${row.target_language})`);
  try {
    const result = await generateWordInfo(
      row.word,
      row.target_language,
      row.context ?? undefined,
      row.user_translation ?? undefined
    );
    const latencyMs = Date.now() - startedAt;
    const costUsd = estimateCostUsd(result.model, result.inputTokens, result.outputTokens);
    const wordInfoJson = JSON.stringify(result.wordInfo);

    upsertStoredWord({
      word: row.word,
      targetLanguage: row.target_language,
      wordInfoJson,
      model: result.model,
      context: row.context,
      userTranslation: row.user_translation,
    });

    insertWordInfoLog({
      word: row.word,
      targetLanguage: row.target_language,
      userTranslation: row.user_translation,
      context: row.context,
      wordInfoJson,
      model: result.model,
      inputTokens: result.inputTokens,
      outputTokens: result.outputTokens,
      costUsd,
      status: "success",
      errorMessage: null,
      latencyMs,
      cacheHit: false,
    });

    logger.info(`admin: regenerated stored word #${id} "${row.word}" latencyMs=${latencyMs}`);
    res.redirect(`/admin/words/${id}`);
  } catch (error) {
    const latencyMs = Date.now() - startedAt;
    const errorMessage = error instanceof Error ? error.message : String(error);

    insertWordInfoLog({
      word: row.word,
      targetLanguage: row.target_language,
      userTranslation: row.user_translation,
      context: row.context,
      wordInfoJson: null,
      model: config.wordInfoModel,
      inputTokens: 0,
      outputTokens: 0,
      costUsd: 0,
      status: "error",
      errorMessage,
      latencyMs,
      cacheHit: false,
    });

    logger.error(`admin: regenerate failed word #${id} "${row.word}" error=${errorMessage}`);
    res.status(500).type("html").send(
      renderPage(
        "再生成に失敗しました",
        "",
        `<p>再生成に失敗しました: ${escapeHtml(errorMessage)}</p><p><a href="/admin/words/${id}">← 詳細に戻る</a></p>`
      )
    );
  }
});

// 単語の「単体読み上げ」音声（text == 単語）だけを作り直す。定義・例文の音声には触れない。
// 恒久キャッシュ（tts_audio）に固定された不明瞭な合成を作り直す運用ツール。
adminRouter.post("/words/:id/regenerate-audio", async (req, res) => {
  const id = Number(req.params.id);
  const row = getStoredWordById(id);
  if (!row) {
    res.status(404).type("html").send(
      renderPage("単語が見つかりません", "", '<p>指定された単語は存在しません。</p><p><a href="/admin/words">← 一覧に戻る</a></p>')
    );
    return;
  }

  const startedAt = Date.now();
  logger.info(`admin: regenerate word reading audio #${id} "${row.word}"`);
  try {
    const models = await regenerateWordReadingAudio(row.word);
    logger.info(
      `admin: regenerated word reading audio #${id} "${row.word}" models=${models.join(",")} latencyMs=${Date.now() - startedAt}`
    );
    res.redirect(`/admin/words/${id}`);
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error);
    logger.error(`admin: regenerate word reading audio failed #${id} "${row.word}" error=${errorMessage}`);
    res.status(500).type("html").send(
      renderPage(
        "読み上げ音声の再生成に失敗しました",
        "",
        `<p>再生成に失敗しました: ${escapeHtml(errorMessage)}</p><p><a href="/admin/words/${id}">← 詳細に戻る</a></p>`
      )
    );
  }
});

// WAVフォーマットは固定（24kHz/16bit/mono、tts.ts）のため、ヘッダ44バイトを除いた
// PCMバイト数から再生時間を算出できる（48,000 bytes/sec）。
function formatTtsDuration(byteSize: number): string {
  const totalSeconds = Math.max(0, byteSize - 44) / 48000;
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = Math.round(totalSeconds % 60);
  if (seconds === 60) return `${minutes + 1}:00`;
  return `${minutes}:${String(seconds).padStart(2, "0")}`;
}

adminRouter.get("/tts", (_req, res) => {
  const rows = listTtsAudio();
  // input_tokens = output_tokens = 0 はトークン記録前（マイグレーション前）の既存行とみなす
  const hasCostRecord = (row: { input_tokens: number; output_tokens: number }) =>
    row.input_tokens !== 0 || row.output_tokens !== 0;
  const totalCostUsd = rows.filter(hasCostRecord).reduce((sum, row) => sum + row.cost_usd, 0);

  const totalBytes = rows.reduce((sum, row) => sum + row.byte_size, 0);

  const tableRows = rows
    .map((row) => {
      const preview = row.text.length > 80 ? `${row.text.slice(0, 80)}…` : row.text;
      const cost = hasCostRecord(row) ? `$${row.cost_usd.toFixed(4)}` : `<span class="faint">—</span>`;
      return `
        <tr class="log-row">
          <td class="mono dim">#${row.id}</td>
          <td class="mono dim">${escapeHtml(formatSeattleTime(row.created_at))}</td>
          <td>${escapeHtml(preview)}</td>
          <td>${escapeHtml(row.voice)}</td>
          <td class="dim">${escapeHtml(row.model)}</td>
          <td class="mono dim">${(row.byte_size / 1024).toFixed(0)} KB</td>
          <td class="mono dim">${formatTtsDuration(row.byte_size)}</td>
          <td class="mono">${cost}</td>
          <td><audio controls preload="none" src="/admin/tts/${row.id}/audio" style="width:220px;height:32px;"></audio></td>
          <td>
            <form method="post" action="/admin/tts/${row.id}/delete"
                  onsubmit="return confirm('このTTS音声を削除します。よろしいですか？（同じテキストが再生されれば再合成されます）')">
              <button type="submit" class="btn btn-danger">削除</button>
            </form>
          </td>
        </tr>
      `;
    })
    .join("\n");

  res.type("html").send(
    renderPage(
      "ESL Assistant - TTS一覧",
      "",
      `
        <h1>保存済みTTS音声一覧</h1>
        <p class="page-sub">料金合計はトークン記録のある行のみの合算</p>
        <div class="stats">
          <div class="stat"><div class="lbl">保存件数</div><div class="val">${rows.length}<small>件</small></div></div>
          <div class="stat"><div class="lbl">料金合計</div><div class="val">$${totalCostUsd.toFixed(4)}</div></div>
          <div class="stat"><div class="lbl">合計サイズ</div><div class="val">${(totalBytes / 1024 / 1024).toFixed(1)}<small>MB</small></div></div>
        </div>
        <div class="card">
          <table>
            <thead>
              <tr>
                <th>ID</th><th>作成日時</th><th>テキスト</th><th>声</th><th>モデル</th>
                <th>サイズ</th><th>長さ</th><th>料金</th><th>試聴</th><th></th>
              </tr>
            </thead>
            <tbody>${tableRows}</tbody>
          </table>
        </div>
      `,
      "tts"
    )
  );
});

adminRouter.get("/illustrations", (_req, res) => {
  const rows = listWordIllustrations();
  const totalCostUsd = rows.reduce((sum, row) => sum + row.cost_usd, 0);
  const totalBytes = rows.reduce((sum, row) => sum + row.byte_size, 0);

  const tableRows = rows
    .map(
      (row) => `
        <tr class="log-row">
          <td class="mono dim">#${row.id}</td>
          <td class="mono dim">${escapeHtml(formatSeattleTime(row.created_at))}</td>
          <td><a href="/admin/illustrations/${row.id}/image" target="_blank"><img class="thumb" src="/admin/illustrations/${row.id}/image" alt="${escapeHtml(row.word)}" style="max-width:120px;max-height:120px;" loading="lazy"></a></td>
          <td><strong>${escapeHtml(row.word)}</strong><br><span class="dim">${escapeHtml(row.target_language)} / 第${row.sense_index + 1}義</span></td>
          <td class="prompt-cell dim">${escapeHtml(row.prompt)}</td>
          <td class="dim">${escapeHtml(row.model)}</td>
          <td class="mono dim">${(row.byte_size / 1024).toFixed(0)} KB</td>
          <td class="mono">$${row.cost_usd.toFixed(4)}<br><span class="faint">in:${row.input_tokens} / out:${row.output_tokens}</span></td>
          <td>
            <div class="row-actions">
              <form method="post" action="/admin/illustrations/${row.id}/regenerate"
                    onsubmit="return confirm('このイラストを再生成します。現在の画像は上書きされます。よろしいですか？')">
                <button type="submit" class="btn btn-primary">再生成</button>
              </form>
              <form method="post" action="/admin/illustrations/${row.id}/delete"
                    onsubmit="return confirm('このイラストを削除します。よろしいですか？（アプリから再リクエストされれば再生成されます）')">
                <button type="submit" class="btn btn-danger">削除</button>
              </form>
            </div>
          </td>
        </tr>
      `
    )
    .join("\n");

  res.type("html").send(
    renderPage(
      "ESL Assistant - 単語イラスト",
      `
        .prompt-cell { max-width: 380px; font-size: 11.5px; word-break: break-word; }
        .row-actions { display: flex; flex-direction: column; gap: 8px; }
      `,
      `
        <h1>単語イラスト一覧</h1>
        <p class="page-sub">GPT Image 2 で生成した単語イラスト（第1義の自動生成）</p>
        <div class="stats">
          <div class="stat"><div class="lbl">保存件数</div><div class="val">${rows.length}<small>件</small></div></div>
          <div class="stat"><div class="lbl">料金合計</div><div class="val">$${totalCostUsd.toFixed(4)}</div></div>
          <div class="stat"><div class="lbl">合計サイズ</div><div class="val">${(totalBytes / 1024 / 1024).toFixed(1)}<small>MB</small></div></div>
        </div>
        <div class="card">
          <table>
            <thead>
              <tr>
                <th>ID</th><th>作成日時</th><th>イラスト</th><th>単語</th>
                <th>プロンプト</th><th>モデル</th><th>サイズ</th><th>料金</th><th></th>
              </tr>
            </thead>
            <tbody>${tableRows || '<tr><td colspan="9" class="faint">（まだイラストはありません）</td></tr>'}</tbody>
          </table>
        </div>
      `,
      "illustrations"
    )
  );
});

adminRouter.get("/illustrations/:id/image", (req, res) => {
  const id = Number(req.params.id);
  const row = getWordIllustrationById(id);
  if (!row) {
    res.status(404).end();
    return;
  }
  res.sendFile(path.join(config.illustrationsDir, row.filename));
});

adminRouter.post("/illustrations/:id/delete", (req, res) => {
  const id = Number(req.params.id);
  const row = getWordIllustrationById(id);
  if (!row) {
    res.status(404).type("html").send(
      renderPage("イラストが見つかりません", "", '<p>指定されたイラストは存在しません。</p><p><a href="/admin/illustrations">← 一覧に戻る</a></p>')
    );
    return;
  }
  // 行を消してもファイルが残るとディスクを食い続けるため、ファイル→行の順に削除する
  fs.rmSync(path.join(config.illustrationsDir, row.filename), { force: true });
  deleteWordIllustration(id);
  logger.info(`admin: deleted word illustration #${id} "${row.word}" (${row.byte_size} bytes)`);
  res.redirect("/admin/illustrations");
});

adminRouter.post("/illustrations/:id/regenerate", async (req, res) => {
  const id = Number(req.params.id);
  const row = getWordIllustrationById(id);
  if (!row) {
    res.status(404).type("html").send(
      renderPage("イラストが見つかりません", "", '<p>指定されたイラストは存在しません。</p><p><a href="/admin/illustrations">← 一覧に戻る</a></p>')
    );
    return;
  }

  const startedAt = Date.now();
  logger.info(`admin: regenerate word illustration #${id} "${row.word}"`);
  try {
    // 保存済みプロンプトで作りなおす（単語情報が更新されていてもプロンプトは据え置きの割り切り）
    const { png, inputTokens, outputTokens } = await generateIllustration(row.prompt);
    const costUsd = estimateCostUsd(row.model, inputTokens, outputTokens);
    fs.writeFileSync(path.join(config.illustrationsDir, row.filename), png);
    upsertWordIllustration({
      word: row.word,
      targetLanguage: row.target_language,
      senseIndex: row.sense_index,
      prompt: row.prompt,
      model: row.model,
      keyHash: row.key_hash,
      filename: row.filename,
      byteSize: png.length,
      inputTokens,
      outputTokens,
      costUsd,
    });
    logger.info(`admin: regenerated word illustration #${id} "${row.word}" latencyMs=${Date.now() - startedAt}`);
    res.redirect("/admin/illustrations");
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error);
    logger.error(`admin: regenerate illustration failed #${id} "${row.word}" error=${errorMessage}`);
    res.status(500).type("html").send(
      renderPage(
        "再生成に失敗しました",
        "",
        `<p>再生成に失敗しました: ${escapeHtml(errorMessage)}</p><p><a href="/admin/illustrations">← 一覧に戻る</a></p>`
      )
    );
  }
});

// このアプリでの各モデルの用途（設定値から逆引き）。料金ページの表示用
function modelUsage(model: string): string {
  const usages: string[] = [];
  if (model === config.ocrModel) usages.push("OCR");
  if (model === config.translateModel) usages.push("翻訳");
  if (model === config.wordInfoModel) usages.push("単語情報");
  if (model === config.wordNormalizeModel) usages.push("単語正規化");
  if (model === config.writingFeedbackModel) usages.push("作文添削");
  if (model === "gemini-2.5-flash-preview-tts") usages.push("TTS (flash)");
  if (model === "gemini-2.5-pro-preview-tts") usages.push("TTS (pro)");
  if (model === ILLUSTRATION_MODEL) usages.push("単語イラスト");
  return usages.join(" / ");
}

// 利用料金ページ専用のスタイル（キャリアpill・構成比バー・日次バー・注記）
const USAGE_STYLE = `
  .note { color: #8B98A5; font-size: 12px; margin: 0 0 18px; max-width: 980px; line-height: 1.7; }
  .note strong { color: #D29922; font-weight: 600; }
  .share-cell { white-space: nowrap; }
  .sharebar { display: inline-block; width: 110px; height: 8px; background: #1F2A35; border-radius: 4px; overflow: hidden; vertical-align: middle; margin-right: 8px; }
  .sharebar > span { display: block; height: 100%; background: #38BDF8; }
  .sharepct { color: #8B98A5; font-size: 12px; }
  .prov { display: inline-block; font-size: 11.5px; font-weight: 600; padding: 1px 8px; border-radius: 4px; white-space: nowrap; font-family: ui-monospace, "SF Mono", Menlo, Consolas, monospace; }
  .prov + .prov { margin-left: 4px; }
  .prov-openai { color: #3FB950; background: rgba(63,185,80,0.12); border: 1px solid rgba(63,185,80,0.35); }
  .prov-gemini { color: #58A6FF; background: rgba(88,166,255,0.12); border: 1px solid rgba(88,166,255,0.35); }
  .prov-claude { color: #E3935D; background: rgba(227,147,93,0.14); border: 1px solid rgba(227,147,93,0.40); }
  .prov-other  { color: #8B98A5; background: rgba(139,152,165,0.12); border: 1px solid rgba(139,152,165,0.30); }
  .approx-tag { color: #D29922; font-size: 11px; margin-left: 6px; cursor: help; }
  .daychart { max-width: 980px; }
  .daychart .bars { display: flex; align-items: flex-end; gap: 2px; height: 120px; padding: 10px 12px; background: #111820; border: 1px solid #1F2A35; border-radius: 10px; }
  .daychart .daybar { flex: 1 1 0; display: flex; align-items: flex-end; height: 100%; min-width: 2px; }
  .daychart .daybar > span { width: 100%; background: #38BDF8; border-radius: 2px 2px 0 0; }
  .daychart .axis { display: flex; justify-content: space-between; font-size: 11px; color: #66737F; padding: 4px 2px 0; }
`;

// 機能キー → 表示名 + 既存ログページへのリンク
const USAGE_FEATURE_META: Record<UsageFeature, { label: string; href: string }> = {
  ocr: { label: "OCR・翻訳", href: "/admin" },
  transcription: { label: "音声文字起こし・翻訳", href: "/admin/transcriptions" },
  document: { label: "ドキュメント抽出・翻訳", href: "/admin/documents" },
  "word-info": { label: "単語情報", href: "/admin/word-info" },
  "word-normalize": { label: "単語正規化", href: "/admin/word-normalize" },
  "writing-feedback": { label: "作文添削", href: "/admin/writing-feedback" },
  tts: { label: "TTS音声", href: "/admin/tts" },
  illustrations: { label: "単語イラスト", href: "/admin/illustrations" },
  quiz: { label: "単語クイズ", href: "/admin/quiz-questions" },
};

function providerPill(provider: Provider): string {
  return `<span class="prov prov-${provider}">${escapeHtml(providerLabel(provider))}</span>`;
}

function shareBar(share: number): string {
  const pct = (share * 100).toFixed(1);
  return `<span class="sharebar"><span style="width:${pct}%"></span></span><span class="sharepct">${pct}%</span>`;
}

adminRouter.get("/usage", (_req, res) => {
  const { summary, byProvider, byFeature, byModel, daily, dailyMaxCostUsd, dailyDays } = getUsageCostReport(30);

  const emptyRow = (cols: number) => `<tr><td colspan="${cols}" class="faint">データなし</td></tr>`;

  const providerRows = byProvider.length
    ? byProvider
        .map(
          (r) => `
        <tr class="log-row">
          <td>${providerPill(r.provider)}</td>
          <td class="mono"><strong>$${r.costUsd.toFixed(4)}</strong></td>
          <td class="share-cell">${shareBar(r.share)}</td>
          <td class="mono dim">${r.count}</td>
        </tr>`
        )
        .join("\n")
    : emptyRow(4);

  const featureRows = byFeature.length
    ? byFeature
        .map((r) => {
          const meta = USAGE_FEATURE_META[r.feature];
          const approx = USAGE_APPROX_FEATURES.has(r.feature)
            ? `<span class="approx-tag" title="キャッシュ保存分のみの集計。再生成・削除の履歴は残らないため総額は下限の概算">≈概算</span>`
            : "";
          return `
        <tr class="log-row">
          <td><a href="${meta.href}">${escapeHtml(meta.label)}</a>${approx}</td>
          <td>${r.providers.map(providerPill).join("")}</td>
          <td class="mono"><strong>$${r.costUsd.toFixed(4)}</strong></td>
          <td class="share-cell">${shareBar(r.share)}</td>
          <td class="mono dim">in:${r.inputTokens.toLocaleString("en-US")}<br>out:${r.outputTokens.toLocaleString("en-US")}</td>
          <td class="mono dim">${r.count}</td>
          <td class="mono dim">${r.latestCreatedAt ? escapeHtml(formatSeattleTime(r.latestCreatedAt)) : "—"}</td>
        </tr>`;
        })
        .join("\n")
    : emptyRow(7);

  const modelRows = byModel.length
    ? byModel
        .map(
          (r) => `
        <tr class="log-row">
          <td class="mono">${escapeHtml(r.model)}</td>
          <td>${providerPill(r.provider)}</td>
          <td class="mono"><strong>$${r.costUsd.toFixed(4)}</strong></td>
          <td class="share-cell">${shareBar(r.share)}</td>
          <td class="mono dim">${r.count}</td>
        </tr>`
        )
        .join("\n")
    : emptyRow(5);

  const dayBars = daily
    .map((d) => {
      const h =
        dailyMaxCostUsd > 0 && d.costUsd > 0 ? Math.max(4, Math.round((d.costUsd / dailyMaxCostUsd) * 100)) : 0;
      const bar = h > 0 ? `<span style="height:${h}%"></span>` : "";
      return `<div class="daybar" title="${d.date}: $${d.costUsd.toFixed(4)}">${bar}</div>`;
    })
    .join("");
  const firstDay = daily.length ? daily[0].date : "";
  const lastDay = daily.length ? daily[daily.length - 1].date : "";

  res.type("html").send(
    renderPage(
      "利用料金 - ESL Assistant",
      USAGE_STYLE,
      `
        <h1>AI利用料金</h1>
        <p class="page-sub">全機能のAPI実利用コストをキャリア・機能・モデル・日次で集計（時刻は ${SEATTLE_TZ} 基準）。単価表は<a href="/admin/pricing">AI料金（単価）</a>を参照。</p>
        <p class="note"><strong>注記:</strong> TTS音声・単語イラスト・単語クイズ（<span class="approx-tag">≈概算</span>）はキャッシュ保存分のみの集計で、再生成・削除の履歴が残らないため総額は<strong>下限の概算</strong>です。他の4機能（OCR・翻訳／音声文字起こし／単語情報／作文添削）は呼び出しごとの追記ログなので累計として正確です。</p>
        <div class="stats">
          <div class="stat"><div class="lbl">総コスト</div><div class="val">$${summary.totalCostUsd.toFixed(2)}</div></div>
          <div class="stat"><div class="lbl">当月コスト</div><div class="val">$${summary.monthCostUsd.toFixed(2)}</div></div>
          <div class="stat"><div class="lbl">当日コスト</div><div class="val">$${summary.todayCostUsd.toFixed(2)}</div></div>
          <div class="stat"><div class="lbl">イベント数</div><div class="val">${summary.totalEvents.toLocaleString("en-US")}<small>件</small></div></div>
        </div>

        <h2>キャリア別</h2>
        <div class="card">
          <table>
            <thead><tr><th>キャリア</th><th>コスト</th><th>構成比</th><th>件数</th></tr></thead>
            <tbody>${providerRows}</tbody>
          </table>
        </div>

        <h2>機能別</h2>
        <div class="card">
          <table>
            <thead><tr><th>機能</th><th>キャリア</th><th>コスト</th><th>構成比</th><th>トークン</th><th>件数</th><th>直近利用</th></tr></thead>
            <tbody>${featureRows}</tbody>
          </table>
        </div>

        <h2>モデル別</h2>
        <div class="card">
          <table>
            <thead><tr><th>モデル</th><th>キャリア</th><th>コスト</th><th>構成比</th><th>件数</th></tr></thead>
            <tbody>${modelRows}</tbody>
          </table>
        </div>

        <h2>日次推移（直近${dailyDays}日）</h2>
        <div class="daychart">
          <div class="bars">${dayBars}</div>
          <div class="axis"><span>${firstDay}</span><span>${lastDay}</span></div>
        </div>
      `,
      "usage"
    )
  );
});

adminRouter.get("/pricing", (_req, res) => {
  const pricing = getCurrentPricing();
  const state = getPricingState();
  const historyRows = listRecentSystemLogs(100)
    .filter((log) => log.category === "pricing")
    .slice(0, 10);

  // Claude（LiteLLM自動更新）→ Gemini TTS（Google公式ページ自動更新）→ 画像生成（手動固定値）の順に表示する
  const groups: Array<{ source: string; defaults: Record<string, { input: number; output: number }> }> = [
    { source: "LiteLLM（24時間ごと自動更新）", defaults: DEFAULT_PRICING },
    { source: "Google公式ページ（24時間ごと自動更新）", defaults: DEFAULT_TTS_PRICING },
    { source: "手動（OpenAI公式ページの固定値）", defaults: DEFAULT_IMAGE_PRICING },
  ];

  const priceCell = (value: number, defaultValue: number) =>
    value === defaultValue
      ? `<td class="mono price-cell">$${value.toFixed(2)}</td>`
      : `<td class="mono price-cell changed">$${value.toFixed(2)} <span class="faint">(既定 $${defaultValue.toFixed(2)})</span></td>`;

  const tableRows = groups
    .flatMap(({ source, defaults }) =>
      Object.keys(defaults).map((model) => {
        const current = pricing[model] ?? defaults[model];
        return `
          <tr class="log-row">
            <td class="mono"><strong>${escapeHtml(model)}</strong></td>
            <td>${escapeHtml(modelUsage(model))}</td>
            <td class="dim">${escapeHtml(source)}</td>
            ${priceCell(current.input, defaults[model].input)}
            ${priceCell(current.output, defaults[model].output)}
          </tr>
        `;
      })
    )
    .join("\n");

  const history = historyRows
    .map(
      (log) => `
        <tr class="log-row ${log.level === "error" ? "level-error" : log.level === "warn" ? "level-warn" : ""}">
          <td class="mono dim">${escapeHtml(formatSeattleTime(log.created_at))}</td>
          <td class="history-msg">${escapeHtml(log.message)}</td>
        </tr>
      `
    )
    .join("\n");

  res.type("html").send(
    renderPage(
      "ESL Assistant - AI料金",
      `
        .price-cell { text-align: right; white-space: nowrap; }
        .price-cell.changed { color: #D29922; }
        .level-warn td { color: #D29922; }
        .level-error td { color: #F85149; }
        .refresh-bar { display: flex; align-items: center; gap: 12px; margin: 0 0 18px; }
        .history-msg { word-break: break-all; }
      `,
      `
        <h1>AIモデル料金</h1>
        <p class="page-sub">適用中の単価（100万トークンあたり・USD）。取得失敗時や検証ガード不合格時は直前の値を維持する</p>
        <div class="stats">
          <div class="stat"><div class="lbl">登録モデル数</div><div class="val">${Object.keys(pricing).length}<small>件</small></div></div>
          <div class="stat"><div class="lbl">最終更新</div><div class="val" style="font-size:16px; line-height:2;">${
            state ? escapeHtml(formatSeattleTime(state.updated_at)) : "（未取得）"
          }</div></div>
        </div>
        <div class="refresh-bar">
          <form method="post" action="/admin/pricing/refresh">
            <button type="submit" class="btn btn-primary">今すぐ更新チェック</button>
          </form>
          <span class="faint">LiteLLM と Google 公式ページを即時チェックし、結果を更新履歴に記録します</span>
        </div>
        <div class="card">
          <table>
            <thead>
              <tr>
                <th>モデル</th><th>用途</th><th>取得元</th>
                <th style="text-align:right">Input / 1M</th><th style="text-align:right">Output / 1M</th>
              </tr>
            </thead>
            <tbody>${tableRows}</tbody>
          </table>
        </div>
        <h2>更新履歴（直近${historyRows.length}件）</h2>
        <div class="card">
          <table>
            <thead>
              <tr><th>日時</th><th>結果</th></tr>
            </thead>
            <tbody>${history || '<tr><td colspan="2" class="faint">（記録なし）</td></tr>'}</tbody>
          </table>
        </div>
      `,
      "pricing"
    )
  );
});

adminRouter.post("/pricing/refresh", async (_req, res) => {
  logger.info("admin: manual pricing refresh requested");
  await fetchAndApplyPricing();
  await fetchAndApplyTtsPricing();
  res.redirect("/admin/pricing");
});

// 汎用のシステムイベントログ（料金表更新チェックなどのサーバ内部イベント）。
// パスは /admin/logs だと既存の OCR ログ詳細 /admin/logs/:id と紛らわしいため system-logs にしている。
adminRouter.get("/system-logs", (_req, res) => {
  const logs = listRecentSystemLogs(100);

  const rows = logs
    .map((log) => {
      const levelClass = log.level === "error" ? "level-error" : log.level === "warn" ? "level-warn" : "";
      return `
        <tr class="log-row ${levelClass}">
          <td class="mono dim">#${log.id}</td>
          <td class="mono dim">${escapeHtml(formatSeattleTime(log.created_at))}</td>
          <td class="mono">${escapeHtml(log.category)}</td>
          <td class="mono level-cell">${escapeHtml(log.level)}</td>
          <td>${escapeHtml(log.message)}</td>
        </tr>
      `;
    })
    .join("\n");

  res.type("html").send(
    renderPage(
      "ESL Assistant - システムログ",
      `
        .level-warn .level-cell, .level-warn td:last-child { color: #D29922; }
        .level-error .level-cell, .level-error td:last-child { color: #F85149; }
      `,
      `
        <h1>システムログ</h1>
        <p class="page-sub">直近${logs.length}件のサーバ内部イベント</p>
        <div class="card">
          <table>
            <thead>
              <tr>
                <th>ID</th><th>日時</th><th>カテゴリ</th><th>レベル</th><th>メッセージ</th>
              </tr>
            </thead>
            <tbody>${rows}</tbody>
          </table>
        </div>
      `,
      "logs"
    )
  );
});

adminRouter.get("/tts/:id/audio", (req, res) => {
  const id = Number(req.params.id);
  const row = getTtsAudioById(id);
  if (!row) {
    res.status(404).end();
    return;
  }
  res.sendFile(path.join(config.ttsDir, row.filename));
});

adminRouter.post("/tts/:id/delete", (req, res) => {
  const id = Number(req.params.id);
  const row = getTtsAudioById(id);
  if (!row) {
    res.status(404).type("html").send(
      renderPage("TTS音声が見つかりません", "", '<p>指定されたTTS音声は存在しません。</p><p><a href="/admin/tts">← 一覧に戻る</a></p>')
    );
    return;
  }
  // 行を消してもファイルが残るとディスクを食い続けるため、ファイル→行の順に削除する
  fs.rmSync(path.join(config.ttsDir, row.filename), { force: true });
  deleteTtsAudio(id);
  logger.info(`admin: deleted tts audio #${id} (${row.voice}/${row.model}, ${row.byte_size} bytes)`);
  res.redirect("/admin/tts");
});

// ---- 音声文字起こし・翻訳ログ（/api/transcribe-translate。docs/plans/audio-transcription-translation.md Phase 5）----

// 一覧に長文をそのまま流し込むと行が崩れるため、英文・訳ともに短くプレビューする（全文は title で確認）。
function transcriptPreview(text: string | null): string {
  if (!text) return '<span class="faint">(なし)</span>';
  const preview = text.length > 120 ? `${text.slice(0, 120)}…` : text;
  return `<span title="${escapeHtml(text)}">${escapeHtml(preview)}</span>`;
}

adminRouter.get("/transcriptions", (_req, res) => {
  const logs = listRecentTranscriptionLogs(100);

  const totalCostUsd = logs.reduce((sum, log) => sum + log.cost_usd, 0);
  const errorCount = logs.filter((log) => log.status !== "success").length;
  const avgLatencySec = logs.length ? logs.reduce((sum, log) => sum + log.latency_ms, 0) / logs.length / 1000 : 0;

  const tableRows = logs
    .map((log) => {
      const player = log.audio_filename
        ? `<audio controls preload="none" src="/admin/transcriptions/${log.id}/audio" style="width:220px;height:32px;"></audio>`
        : `<span class="faint">(なし)</span>`;
      return `
        <tr class="log-row">
          <td class="mono dim">#${log.id}</td>
          <td class="mono dim">${escapeHtml(formatSeattleTime(log.created_at))}</td>
          <td style="min-width:120px;">${log.title ? escapeHtml(log.title) : '<span class="faint">—</span>'}</td>
          <td>
            ${player}
            <div class="faint" style="margin-top:4px;">${escapeHtml(log.media_type)} / ${(log.byte_size / 1024).toFixed(0)} KB</div>
          </td>
          <td style="min-width:180px;max-width:280px;">
            ${transcriptPreview(log.english_text)}
            ${log.english_text ? `<div style="margin-top:4px;"><a href="/admin/transcriptions/${log.id}/text" target="_blank">印刷用表示</a></div>` : ""}
          </td>
          <td style="min-width:180px;max-width:280px;">
            ${transcriptPreview(log.translated_text)}
            ${log.translated_text ? `<div style="margin-top:4px;"><a href="/admin/transcriptions/${log.id}/translation" target="_blank">印刷用表示</a></div>` : ""}
          </td>
          <td>
            文字起こし: <strong>${escapeHtml(log.transcription_model)}</strong> <span class="dim">(in:${log.transcription_input_tokens} / out:${log.transcription_output_tokens})</span><br>
            翻訳: ${log.translate_model ? `${escapeHtml(log.translate_model)} <span class="dim">(in:${log.translate_input_tokens} / out:${log.translate_output_tokens})</span>` : "(なし)"}
          </td>
          <td class="mono">
            <strong>$${log.cost_usd.toFixed(5)}</strong><br>
            <span class="faint">文字起こし $${log.transcription_cost_usd.toFixed(5)} / 翻訳 $${log.translate_cost_usd.toFixed(5)}</span>
          </td>
          <td>${statusLabel(log)}${log.error_message ? `<div class="err-note">${escapeHtml(log.error_message)}</div>` : ""}</td>
          <td class="mono dim">${log.latency_ms}ms</td>
          <td>
            <form method="post" action="/admin/transcriptions/${log.id}/delete"
                  onsubmit="return confirm('この文字起こしログと保存音声を削除します。よろしいですか？')">
              <button type="submit" class="btn btn-danger">削除</button>
            </form>
          </td>
        </tr>
      `;
    })
    .join("\n");

  res.type("html").send(
    renderPage(
      "ESL Assistant - 音声文字起こしログ",
      "",
      `
        <h1>音声文字起こし・翻訳ログ</h1>
        <p class="page-sub">直近${logs.length}件の文字起こし（Gemini）＋英→日翻訳（Claude）リクエスト</p>
        <div class="stats">
          <div class="stat"><div class="lbl">直近件数</div><div class="val">${logs.length}<small>件</small></div></div>
          <div class="stat"><div class="lbl">コスト合計</div><div class="val">$${totalCostUsd.toFixed(4)}</div></div>
          <div class="stat${errorCount > 0 ? " alert" : ""}"><div class="lbl">エラー</div><div class="val">${errorCount}<small>件</small></div></div>
          <div class="stat"><div class="lbl">平均処理時間</div><div class="val">${avgLatencySec.toFixed(1)}<small>s</small></div></div>
        </div>
        <div class="card">
          <table>
            <thead>
              <tr>
                <th>ID</th><th>日時</th><th>タイトル</th><th>音声</th><th>英文</th><th>訳</th>
                <th>モデル / トークン</th><th>コスト</th><th>状態</th><th>処理時間</th><th></th>
              </tr>
            </thead>
            <tbody>${tableRows}</tbody>
          </table>
        </div>
      `,
      "transcriptions"
    )
  );
});

adminRouter.get("/transcriptions/:id/audio", (req, res) => {
  const id = Number(req.params.id);
  const row = getTranscriptionLog(id);
  if (!row || !row.audio_filename) {
    res.status(404).end();
    return;
  }
  res.sendFile(path.join(config.audioDir, row.audio_filename));
});

// 文字起こし英文・訳文の印刷用表示（docs/plans/admin-transcription-print-view.md /
// admin-print-views-photo-document-translation.md）。本文は空行区切りの平文なので
// transcriptParagraphsHtml で段落化する。
function sendTranscriptionPrintPage(res: Response, id: number, kind: "text" | "translation"): void {
  const row = getTranscriptionLog(id);
  if (!row) {
    res.status(404).type("html").send(
      renderPage("文字起こしログが見つかりません", "", '<p>指定された文字起こしログは存在しません。</p><p><a href="/admin/transcriptions">← 一覧に戻る</a></p>')
    );
    return;
  }
  const isTranslation = kind === "translation";
  const text = isTranslation ? row.translated_text : row.english_text;
  res.type("html").send(
    renderPrintPageHtml({
      lang: isTranslation ? row.target_language : "en",
      title: row.title?.trim() || `Transcription #${row.id}`,
      meta: `#${row.id} ・ ${formatSeattleTime(row.created_at)}${isTranslation ? ` ・ 訳 (${row.target_language})` : ""}`,
      bodyHtml: text ? transcriptParagraphsHtml(text) : `<p class="no-text">(このログには${isTranslation ? "訳文" : "英文"}がありません)</p>`,
      backHref: "/admin/transcriptions",
    })
  );
}

adminRouter.get("/transcriptions/:id/text", (req, res) => {
  sendTranscriptionPrintPage(res, Number(req.params.id), "text");
});

adminRouter.get("/transcriptions/:id/translation", (req, res) => {
  sendTranscriptionPrintPage(res, Number(req.params.id), "translation");
});

adminRouter.post("/transcriptions/:id/delete", (req, res) => {
  const id = Number(req.params.id);
  const row = getTranscriptionLog(id);
  if (!row) {
    res.status(404).type("html").send(
      renderPage("文字起こしログが見つかりません", "", '<p>指定された文字起こしログは存在しません。</p><p><a href="/admin/transcriptions">← 一覧に戻る</a></p>')
    );
    return;
  }
  // 行を消してもファイルが残るとディスクを食い続けるため、ファイル→行の順に削除する
  if (row.audio_filename) {
    fs.rmSync(path.join(config.audioDir, row.audio_filename), { force: true });
  }
  deleteTranscriptionLog(id);
  logger.info(`admin: deleted transcription log #${id} (${row.media_type}, ${row.byte_size} bytes)`);
  res.redirect("/admin/transcriptions");
});

// ---- ドキュメント抽出・翻訳ログ（/api/document-extract-translate。docs/plans/document-import.md Phase 5）----

// 抽出方式（extraction_method）の日本語ラベル。documentExtract.ts の DocumentExtractionMethod と対応。
const DOCUMENT_METHOD_LABELS: Record<string, string> = {
  "pdf-text": "PDFテキスト層",
  "pdf-ocr": "PDFスキャンOCR",
  docx: "Word (DOCX)",
};

function documentMethodLabel(method: string | null): string {
  if (!method) return "";
  return DOCUMENT_METHOD_LABELS[method] ?? method;
}

// 抽出側（テキスト抽出 or スキャンOCR）のモデル・トークン表示。
// extract_model が入るのはスキャンOCR（Claude）だけで、テキスト層PDF・DOCX はライブラリ抽出（AI不使用）。
function documentExtractSummary(log: DocumentLogRow): string {
  if (!log.extraction_method) return `<span class="faint">-</span>`;
  if (log.extract_model) {
    return `<strong>${escapeHtml(log.extract_model)}</strong> <span class="dim">(in:${log.extract_input_tokens} / out:${log.extract_output_tokens})</span>`;
  }
  return `<span class="dim">ライブラリ抽出（AI不使用）</span>`;
}

// 翻訳側のモデル・トークン表示。スキャンOCR は抽出（Claude）呼び出しに翻訳を統合しており
// 翻訳側は0トークンのため、別課金なしと明示する（OCR・翻訳の isCombinedCall と同じ考え方）。
function documentTranslateSummary(log: DocumentLogRow): string {
  if (!log.extraction_method) return `<span class="faint">-</span>`;
  if (log.extract_model && log.translate_input_tokens === 0 && log.translate_output_tokens === 0) {
    return "抽出呼び出しに統合（追加コストなし）";
  }
  if (!log.translate_model) return "(なし)";
  return `<strong>${escapeHtml(log.translate_model)}</strong> <span class="dim">(in:${log.translate_input_tokens} / out:${log.translate_output_tokens})</span>`;
}

adminRouter.get("/documents", (_req, res) => {
  const logs = listRecentDocumentLogs(100);

  const totalCostUsd = logs.reduce((sum, log) => sum + log.cost_usd, 0);
  const errorCount = logs.filter((log) => log.status !== "success").length;
  const avgLatencySec = logs.length ? logs.reduce((sum, log) => sum + log.latency_ms, 0) / logs.length / 1000 : 0;

  const tableRows = logs
    .map((log) => {
      const method = documentMethodLabel(log.extraction_method);
      const fileCell = log.document_filename
        ? `<a href="/admin/documents/${log.id}/file" target="_blank">${escapeHtml(log.file_kind.toUpperCase())} を開く</a>`
        : `<span class="faint">(なし)</span>`;
      return `
        <tr class="log-row">
          <td class="mono dim">#${log.id}</td>
          <td class="mono dim">${escapeHtml(formatSeattleTime(log.created_at))}</td>
          <td>
            ${fileCell}
            <div class="faint" style="margin-top:4px;">${(log.byte_size / 1024).toFixed(0)} KB${method ? ` / ${escapeHtml(method)}` : ""}</div>
          </td>
          <td style="min-width:180px;max-width:280px;">
            ${transcriptPreview(log.extracted_text)}
            ${log.extracted_text ? `<div style="margin-top:4px;"><a href="/admin/documents/${log.id}/text" target="_blank">印刷用表示</a></div>` : ""}
          </td>
          <td style="min-width:180px;max-width:280px;">
            ${transcriptPreview(log.translated_text)}
            ${log.translated_text ? `<div style="margin-top:4px;"><a href="/admin/documents/${log.id}/translation" target="_blank">印刷用表示</a></div>` : ""}
          </td>
          <td>
            抽出: ${documentExtractSummary(log)}<br>
            翻訳: ${documentTranslateSummary(log)}
          </td>
          <td class="mono">
            <strong>$${log.cost_usd.toFixed(5)}</strong><br>
            <span class="faint">抽出 $${log.extract_cost_usd.toFixed(5)} / 翻訳 $${log.translate_cost_usd.toFixed(5)}</span>
          </td>
          <td>${statusLabel(log)}${log.error_message ? `<div class="err-note">${escapeHtml(log.error_message)}</div>` : ""}</td>
          <td class="mono dim">${log.latency_ms}ms</td>
          <td>
            <form method="post" action="/admin/documents/${log.id}/delete"
                  onsubmit="return confirm('この抽出ログと保存文書を削除します。よろしいですか？')">
              <button type="submit" class="btn btn-danger">削除</button>
            </form>
          </td>
        </tr>
      `;
    })
    .join("\n");

  res.type("html").send(
    renderPage(
      "ESL Assistant - ドキュメント抽出ログ",
      "",
      `
        <h1>ドキュメント抽出・翻訳ログ</h1>
        <p class="page-sub">直近${logs.length}件の PDF / Word 抽出（テキスト層 or スキャンOCR）＋翻訳リクエスト</p>
        <div class="stats">
          <div class="stat"><div class="lbl">直近件数</div><div class="val">${logs.length}<small>件</small></div></div>
          <div class="stat"><div class="lbl">コスト合計</div><div class="val">$${totalCostUsd.toFixed(4)}</div></div>
          <div class="stat${errorCount > 0 ? " alert" : ""}"><div class="lbl">エラー</div><div class="val">${errorCount}<small>件</small></div></div>
          <div class="stat"><div class="lbl">平均処理時間</div><div class="val">${avgLatencySec.toFixed(1)}<small>s</small></div></div>
        </div>
        <div class="card">
          <table>
            <thead>
              <tr>
                <th>ID</th><th>日時</th><th>文書</th><th>抽出英文</th><th>訳</th>
                <th>モデル / トークン</th><th>コスト</th><th>状態</th><th>処理時間</th><th></th>
              </tr>
            </thead>
            <tbody>${tableRows || '<tr><td colspan="10" class="dim">まだドキュメント抽出リクエストはありません。</td></tr>'}</tbody>
          </table>
        </div>
      `,
      "documents"
    )
  );
});

adminRouter.get("/documents/:id/file", (req, res) => {
  const id = Number(req.params.id);
  const row = getDocumentLog(id);
  if (!row || !row.document_filename) {
    res.status(404).end();
    return;
  }
  res.sendFile(path.join(config.documentsDir, row.document_filename));
});

// ドキュメント英文・訳文の印刷用表示（docs/plans/admin-print-views-photo-document-translation.md）。
// 抽出結果はスキャンOCR時に Markdown を含むため renderMarkdown で組む
// （テキスト層PDF・DOCX の平文もそのまま段落として描画される）。
function sendDocumentPrintPage(res: Response, id: number, kind: "text" | "translation"): void {
  const row = getDocumentLog(id);
  if (!row) {
    res.status(404).type("html").send(
      renderPage("ドキュメントログが見つかりません", "", '<p>指定されたドキュメントログは存在しません。</p><p><a href="/admin/documents">← 一覧に戻る</a></p>')
    );
    return;
  }
  const isTranslation = kind === "translation";
  const text = isTranslation ? row.translated_text : row.extracted_text;
  res.type("html").send(
    renderPrintPageHtml({
      lang: isTranslation ? row.target_language : "en",
      title: row.title?.trim() || `Document #${row.id}`,
      meta: `#${row.id} ・ ${formatSeattleTime(row.created_at)}${isTranslation ? ` ・ 訳 (${row.target_language})` : ""}`,
      bodyHtml: text ? renderMarkdown(text) : `<p class="no-text">(このログには${isTranslation ? "訳文" : "英文"}がありません)</p>`,
      backHref: "/admin/documents",
    })
  );
}

adminRouter.get("/documents/:id/text", (req, res) => {
  sendDocumentPrintPage(res, Number(req.params.id), "text");
});

adminRouter.get("/documents/:id/translation", (req, res) => {
  sendDocumentPrintPage(res, Number(req.params.id), "translation");
});

adminRouter.post("/documents/:id/delete", (req, res) => {
  const id = Number(req.params.id);
  const row = getDocumentLog(id);
  if (!row) {
    res.status(404).type("html").send(
      renderPage("抽出ログが見つかりません", "", '<p>指定された抽出ログは存在しません。</p><p><a href="/admin/documents">← 一覧に戻る</a></p>')
    );
    return;
  }
  // 行を消してもファイルが残るとディスクを食い続けるため、ファイル→行の順に削除する
  if (row.document_filename) {
    fs.rmSync(path.join(config.documentsDir, row.document_filename), { force: true });
  }
  deleteDocumentLog(id);
  logger.info(`admin: deleted document log #${id} (${row.file_kind}, ${row.byte_size} bytes)`);
  res.redirect("/admin/documents");
});

// ---- 復習クイズ問題（docs/plans/archive/quiz-questions-server-storage.md）----

/// 詳細・削除・再生成の対象指定は (word, targetLanguage) をクエリパラメータで受ける
function quizItemQuery(word: string, targetLanguage: string): string {
  return `word=${encodeURIComponent(word)}&targetLanguage=${encodeURIComponent(targetLanguage)}`;
}

adminRouter.get("/quiz-questions", (_req, res) => {
  const summaries = listQuizQuestionSummaries();
  const totalQuestions = summaries.reduce((sum, row) => sum + row.question_count, 0);
  const totalCost = summaries.reduce((sum, row) => sum + row.total_cost_usd, 0);

  const rows = summaries
    .map(
      (row) => `
        <tr class="log-row">
          <td><strong>${escapeHtml(row.word)}</strong></td>
          <td>${escapeHtml(row.target_language)}</td>
          <td class="mono">${row.question_count}</td>
          <td class="mono">${row.format_count}</td>
          <td class="mono">$${row.total_cost_usd.toFixed(4)}</td>
          <td class="mono dim">${escapeHtml(formatSeattleTime(row.latest_created_at))}</td>
          <td><a href="/admin/quiz-questions/item?${quizItemQuery(row.word, row.target_language)}">詳細 →</a></td>
        </tr>
      `
    )
    .join("\n");

  res.type("html").send(
    renderPage(
      "ESL Assistant - 単語クイズ",
      "",
      `
        <h1>単語クイズ</h1>
        <p class="page-sub">単語×言語ごとに、形式（tc1〜vt2）別の複数バリエーションを保存。iOS はこの中からランダムに出題する</p>
        <div class="stats">
          <div class="stat"><div class="lbl">単語数</div><div class="val">${summaries.length}</div></div>
          <div class="stat"><div class="lbl">問題数</div><div class="val">${totalQuestions}</div></div>
          <div class="stat"><div class="lbl">生成コスト合計</div><div class="val">$${totalCost.toFixed(4)}</div></div>
        </div>
        <div class="card">
          <table>
            <thead>
              <tr>
                <th>単語</th><th>母語</th><th>問題数</th><th>形式数</th><th>コスト</th><th>最終生成</th><th></th>
              </tr>
            </thead>
            <tbody>${rows}</tbody>
          </table>
        </div>
      `,
      "quiz-questions"
    )
  );
});

/// 回答内容の一覧表示用サマリー（4択は正解に✓）
function quizAnswerSummary(question: QuizQuestion): string {
  const answer = question.answer;
  if (answer.type === "typing") {
    const threshold = answer.matchRateThreshold != null ? ` <span class="faint">(一致率 ≥ ${answer.matchRateThreshold})</span>` : "";
    return `入力: ${escapeHtml((answer.acceptedAnswers ?? []).join(" / "))}${threshold}`;
  }
  const options = (answer.options ?? [])
    .map((option, index) =>
      index === answer.correctIndex
        ? `<span class="ok-text">✓ ${escapeHtml(option)}</span>`
        : escapeHtml(option)
    )
    .join("<br>");
  return options;
}

/// audioText のプリ合成済み音声プレイヤー。キャッシュキーは ttsStore の
/// sha256("model|text")（モデルはクイズ音声固定の QUIZ_TTS_MODEL）と一致させる。
/// 未合成（プリ合成失敗など）の場合はその旨を表示する。
function quizAudioCell(audioText: string | null): string {
  if (!audioText) return `<span class="faint">—</span>`;
  const textHash = crypto.createHash("sha256").update(`${QUIZ_TTS_MODEL}|${audioText}`).digest("hex");
  const row = getTtsAudioByHash(textHash);
  if (!row) return `<span class="faint">音声未合成</span>`;
  return `<audio controls preload="none" src="/admin/tts/${row.id}/audio" style="width:220px;height:32px;"></audio>`;
}

adminRouter.get("/quiz-questions/item", (req, res) => {
  const word = String(req.query.word ?? "");
  const targetLanguage = String(req.query.targetLanguage ?? "");
  const rows = listQuizQuestions(word, targetLanguage);
  if (rows.length === 0) {
    res.status(404).type("html").send(
      renderPage(
        "単語クイズが見つかりません",
        "",
        '<p>指定された単語の問題は存在しません。</p><p><a href="/admin/quiz-questions">← 一覧に戻る</a></p>'
      )
    );
    return;
  }

  const totalCost = rows.reduce((sum, row) => sum + row.cost_usd, 0);
  const tableRows = rows
    .map((row) => {
      const question = JSON.parse(row.question_json) as QuizQuestion;
      const prompt = [
        question.displayText ? `表示: ${escapeHtml(question.displayText)}` : "",
        question.audioText ? `<span class="dim">音声: ${escapeHtml(question.audioText)}</span>` : "",
        question.promptIllustrationWord
          ? `<span class="dim">イラスト: ${escapeHtml(question.promptIllustrationWord)}</span>`
          : "",
      ]
        .filter(Boolean)
        .join("<br>");
      return `
        <tr class="log-row">
          <td class="mono"><strong>${escapeHtml(row.format)}</strong> <span class="faint">v${row.variant_index}</span></td>
          <td>${escapeHtml(question.instruction)}${prompt ? `<br>${prompt}` : ""}</td>
          <td>${quizAudioCell(question.audioText)}</td>
          <td>${quizAnswerSummary(question)}</td>
          <td class="dim">${escapeHtml(row.model)}</td>
          <td class="mono dim">$${row.cost_usd.toFixed(4)}</td>
        </tr>
      `;
    })
    .join("\n");

  const body = `
    <p><a href="/admin/quiz-questions">← 一覧に戻る</a></p>
    <h1>単語クイズ: ${escapeHtml(rows[0].word)} <span class="dim">(${escapeHtml(targetLanguage)})</span></h1>
    <p class="page-sub">全${rows.length}問 / 生成コスト $${totalCost.toFixed(4)} / 最終生成 ${escapeHtml(formatSeattleTime(rows[0].created_at))}</p>

    <div class="action-buttons" style="display:flex; gap:12px; margin:16px 0 24px;">
      <form method="post" action="/admin/quiz-questions/regenerate?${quizItemQuery(rows[0].word, targetLanguage)}"
            onsubmit="return confirm('この単語の問題を再生成します。現在の問題は置き換えられます。よろしいですか？')">
        <button type="submit" class="btn btn-primary">再生成する</button>
      </form>
      <form method="post" action="/admin/quiz-questions/delete?${quizItemQuery(rows[0].word, targetLanguage)}"
            onsubmit="return confirm('この単語の問題を削除します。よろしいですか？（アプリの復習開始時に自動で再生成されます）')">
        <button type="submit" class="btn btn-danger">削除する</button>
      </form>
    </div>

    <div class="card">
      <table>
        <thead>
          <tr><th>形式</th><th>問題</th><th>音声</th><th>回答</th><th>モデル</th><th>コスト</th></tr>
        </thead>
        <tbody>${tableRows}</tbody>
      </table>
    </div>
  `;
  res.type("html").send(renderPage(`単語クイズ: ${rows[0].word} - ESL Assistant`, "", body, "quiz-questions"));
});

adminRouter.post("/quiz-questions/delete", (req, res) => {
  const word = String(req.query.word ?? "");
  const targetLanguage = String(req.query.targetLanguage ?? "");
  deleteQuizQuestions(word, targetLanguage);
  logger.info(`admin: deleted quiz questions "${word}" (${targetLanguage})`);
  res.redirect("/admin/quiz-questions");
});

adminRouter.post("/quiz-questions/regenerate", async (req, res) => {
  const word = String(req.query.word ?? "");
  const targetLanguage = String(req.query.targetLanguage ?? "");
  const stored = getStoredWord(word, targetLanguage);
  if (!stored) {
    res.status(404).type("html").send(
      renderPage(
        "単語情報が見つかりません",
        "",
        '<p>素材となる単語情報がありません。先に単語情報を生成してください。</p><p><a href="/admin/quiz-questions">← 一覧に戻る</a></p>'
      )
    );
    return;
  }

  const startedAt = Date.now();
  logger.info(`admin: regenerate quiz questions "${word}" (${targetLanguage})`);
  try {
    const wordInfo = JSON.parse(stored.word_info_json) as WordInfo;
    const result = await generateQuizQuestions(
      word,
      wordInfo,
      listIllustratedWords(targetLanguage),
      listStoredWordTexts(targetLanguage)
    );
    if (result.questions.length === 0) {
      throw new Error(result.errors.join(" / ") || "no questions generated");
    }
    replaceQuizQuestions(
      word,
      targetLanguage,
      result.questions.map((generated) => ({
        word,
        targetLanguage,
        format: generated.question.format,
        variantIndex: generated.variantIndex,
        questionJson: JSON.stringify(generated.question),
        model: generated.model,
        inputTokens: generated.inputTokens,
        outputTokens: generated.outputTokens,
        costUsd:
          generated.model === "rule"
            ? 0
            : estimateCostUsd(generated.model, generated.inputTokens, generated.outputTokens),
      }))
    );
    // 音声出題用の audioText をサーバ側で AI 生成しておく（レスポンスはブロックしない）
    void pregenerateQuizAudio(
      result.questions.map((generated) => generated.question),
      word
    );
    logger.info(
      `admin: regenerated quiz questions "${word}" count=${result.questions.length} latencyMs=${Date.now() - startedAt}`
    );
    res.redirect(`/admin/quiz-questions/item?${quizItemQuery(word, targetLanguage)}`);
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error);
    logger.error(`admin: regenerate quiz questions failed "${word}" error=${errorMessage}`);
    res.status(500).type("html").send(
      renderPage(
        "再生成に失敗しました",
        "",
        `<p>${escapeHtml(errorMessage)}</p><p><a href="/admin/quiz-questions">← 一覧に戻る</a></p>`
      )
    );
  }
});

// ---- コンテンツファイル一覧（docs/plans/admin-content-files-page.md）----

// data/ 配下でファイルを保存しているディレクトリのホワイトリスト。
// 配信エンドポイントの dir 検証を兼ねるため、ここに無いディレクトリには一切触れない。
// TTS音声・単語イラストは専用ページ（/admin/tts・/admin/illustrations）があるため載せない。
const CONTENT_DIRS: Array<{ key: string; label: string; dir: string }> = [
  { key: "images", label: "画像", dir: config.imagesDir },
  { key: "audio", label: "取り込み音声", dir: config.audioDir },
  { key: "documents", label: "ドキュメント", dir: config.documentsDir },
];

const AUDIO_FILE_EXTENSIONS = new Set([".wav", ".mp3", ".m4a", ".aac", ".caf", ".ogg", ".flac"]);

// クエリ由来のファイル名で data/ 外へ出られないよう、区切り文字を含む名前は拒否する
function isSafeContentFilename(name: string): boolean {
  return name.length > 0 && !name.includes("/") && !name.includes("\\") && !name.includes("..") && name === path.basename(name);
}

function listContentFiles(dir: string): Array<{ name: string; size: number; mtimeIso: string }> {
  if (!fs.existsSync(dir)) return [];
  return fs
    .readdirSync(dir, { withFileTypes: true })
    .filter((entry) => entry.isFile() && !entry.name.startsWith("."))
    .map((entry) => {
      const stat = fs.statSync(path.join(dir, entry.name));
      return { name: entry.name, size: stat.size, mtimeIso: stat.mtime.toISOString() };
    })
    .sort((a, b) => (a.mtimeIso < b.mtimeIso ? 1 : -1));
}

function contentFileUrl(dirKey: string, name: string, download: boolean): string {
  return `/admin/content-files/file?dir=${encodeURIComponent(dirKey)}&name=${encodeURIComponent(name)}${download ? "&download=1" : ""}`;
}

const CONTENT_FILES_STYLE = `
  .dir-tabs { display: flex; gap: 8px; margin: 0 0 16px; flex-wrap: wrap; }
  .dir-tab { font-size: 12.5px; font-weight: 600; padding: 6px 14px; border-radius: 6px; border: 1px solid #1F2A35; color: #8B98A5; background: #111820; }
  .dir-tab:hover { color: #E6EDF3; text-decoration: none; }
  .dir-tab.active { color: #fff; background: rgba(56,189,248,0.12); border-color: #38BDF8; }
  .dir-tab .cnt { color: #66737F; font-weight: 400; margin-left: 4px; font-variant-numeric: tabular-nums; }
  .dir-tab.active .cnt { color: #8B98A5; }
`;

adminRouter.get("/content-files", (req, res) => {
  const dirKey = typeof req.query.dir === "string" ? req.query.dir : CONTENT_DIRS[0].key;
  const active = CONTENT_DIRS.find((entry) => entry.key === dirKey);
  if (!active) {
    res.status(400).type("html").send(
      renderPage(
        "不正なディレクトリ",
        "",
        '<p>指定されたディレクトリは存在しません。</p><p><a href="/admin/content-files">← コンテンツファイルに戻る</a></p>'
      )
    );
    return;
  }

  const filesByKey = new Map(CONTENT_DIRS.map((entry) => [entry.key, listContentFiles(entry.dir)]));
  const files = filesByKey.get(active.key) ?? [];
  const totalBytes = files.reduce((sum, file) => sum + file.size, 0);

  const tabs = CONTENT_DIRS.map((entry) => {
    const count = filesByKey.get(entry.key)?.length ?? 0;
    return `<a class="dir-tab${entry.key === active.key ? " active" : ""}" href="/admin/content-files?dir=${entry.key}">${entry.label} <span class="cnt">${count}</span></a>`;
  }).join("\n");

  // audio / documents はアプリ側タイトル（リクエスト時に受信しログに記録）をファイル名で突き合わせて表示。
  // 旧アプリからの送信や title 追加前のファイルはログに無いため — 表示になる。
  const titlesByFilename =
    active.key === "audio" ? getAudioTitlesByFilename() : active.key === "documents" ? getDocumentTitlesByFilename() : null;

  const tableRows = files
    .map((file) => {
      const title = titlesByFilename?.get(file.name);
      const titleCell = titlesByFilename ? `<td>${title ? escapeHtml(title) : '<span class="faint">—</span>'}</td>` : "";
      const inlineUrl = contentFileUrl(active.key, file.name, false);
      const preview =
        active.key === "images"
          ? `<a href="${inlineUrl}" target="_blank"><img src="${inlineUrl}" alt="${escapeHtml(file.name)}" style="max-width:96px;max-height:64px;border-radius:4px;display:block;" loading="lazy"></a>`
          : AUDIO_FILE_EXTENSIONS.has(path.extname(file.name).toLowerCase())
            ? `<audio controls preload="none" src="${inlineUrl}" style="width:220px;height:32px;"></audio>`
            : `<span class="faint">—</span>`;
      return `
        <tr class="log-row">
          ${titleCell}
          <td class="mono">${escapeHtml(file.name)}</td>
          <td class="mono dim">${(file.size / 1024).toFixed(0)} KB</td>
          <td class="mono dim">${escapeHtml(formatSeattleTime(file.mtimeIso))}</td>
          <td>${preview}</td>
          <td><a href="${contentFileUrl(active.key, file.name, true)}">DL</a></td>
        </tr>
      `;
    })
    .join("\n");

  const headerCells = [
    ...(titlesByFilename ? ["タイトル"] : []),
    "ファイル名",
    "サイズ",
    "更新日時",
    active.key === "images" ? "サムネ" : "再生",
    "DL",
  ];

  res.type("html").send(
    renderPage(
      "ESL Assistant - コンテンツファイル",
      CONTENT_FILES_STYLE,
      `
        <h1>コンテンツファイル</h1>
        <p class="page-sub">${escapeHtml(active.dir)}</p>
        <div class="dir-tabs">${tabs}</div>
        <div class="stats">
          <div class="stat"><div class="lbl">ファイル数</div><div class="val">${files.length}<small>件</small></div></div>
          <div class="stat"><div class="lbl">合計サイズ</div><div class="val">${(totalBytes / 1024 / 1024).toFixed(1)}<small>MB</small></div></div>
        </div>
        <div class="card">
          <table>
            <thead>
              <tr>${headerCells.map((label) => `<th>${label}</th>`).join("")}</tr>
            </thead>
            <tbody>${tableRows || `<tr><td colspan="${headerCells.length}" class="faint" style="text-align:center;padding:24px;">（ファイルなし）</td></tr>`}</tbody>
          </table>
        </div>
      `,
      "content-files"
    )
  );
});

adminRouter.get("/content-files/file", (req, res) => {
  const dirKey = req.query.dir;
  const name = req.query.name;
  const entry = typeof dirKey === "string" ? CONTENT_DIRS.find((candidate) => candidate.key === dirKey) : undefined;
  if (!entry || typeof name !== "string" || !isSafeContentFilename(name)) {
    res.status(400).end();
    return;
  }
  const filePath = path.join(entry.dir, name);
  if (!fs.existsSync(filePath) || !fs.statSync(filePath).isFile()) {
    res.status(404).end();
    return;
  }
  if (req.query.download === "1") {
    res.download(filePath, name);
  } else {
    // <audio> のシークに必要な Range 対応・Content-Type 判定は sendFile に任せる
    res.sendFile(filePath);
  }
});
