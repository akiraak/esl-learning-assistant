import path from "path";
import { Router } from "express";
import { marked } from "marked";
import fs from "fs";
import {
  deleteQuizQuestions,
  deleteStoredWord,
  deleteTtsAudio,
  deleteWordIllustration,
  getPricingState,
  getRequestLog,
  getStoredWord,
  getStoredWordById,
  getTtsAudioById,
  getWordIllustrationById,
  getWordInfoLog,
  insertWordInfoLog,
  listIllustratedWords,
  listQuizQuestions,
  listQuizQuestionSummaries,
  listRecentRequestLogs,
  listRecentSystemLogs,
  listRecentWordInfoLogs,
  listStoredWords,
  listStoredWordTexts,
  listTtsAudio,
  listWordIllustrations,
  replaceQuizQuestions,
  RequestLogRow,
  StoredWordRow,
  upsertStoredWord,
  upsertWordIllustration,
  WordInfoLogRow,
} from "./db";
import { config } from "./config";
import { generateWordInfo, type WordInfo } from "./wordInfo";
import { generateQuizQuestions, type QuizQuestion } from "./quizQuestions";
import { generateIllustration, ILLUSTRATION_MODEL } from "./illustration";
import { DEFAULT_IMAGE_PRICING, DEFAULT_PRICING, DEFAULT_TTS_PRICING, estimateCostUsd, getCurrentPricing } from "./pricing";
import { fetchAndApplyPricing, fetchAndApplyTtsPricing } from "./pricingSync";
import { logger } from "./logger";

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

/// Markdown由来の生HTMLタグ注入を防ぐため、パース前に `&`/`<`/`>` のみエスケープする
/// （Markdownの見出し・箇条書き・強調記法は `"` を使わないため対象外）。
function renderMarkdown(value: string | null): string {
  if (!value) return "";
  const escaped = value.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
  return marked.parse(escaped, { async: false, breaks: true }) as string;
}

type NavSection = "ocr" | "word-info" | "words" | "quiz-questions" | "tts" | "illustrations" | "pricing" | "logs";

const NAV_ITEMS: Array<[NavSection, string, string]> = [
  ["ocr", "/admin", "OCR・翻訳ログ"],
  ["word-info", "/admin/word-info", "単語情報ログ"],
  ["words", "/admin/words", "単語一覧"],
  ["quiz-questions", "/admin/quiz-questions", "単語クイズ"],
  ["tts", "/admin/tts", "TTS一覧"],
  ["illustrations", "/admin/illustrations", "単語イラスト"],
  ["pricing", "/admin/pricing", "AI料金"],
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
      `ログ #${log.id} - ESL Assistant`,
      `
        .detail-columns { display: flex; gap: 32px; flex-wrap: wrap; align-items: flex-start; }
        .detail-image-col { flex: 0 0 auto; }
        .detail-image { max-width: 480px; max-height: 640px; border: 1px solid #2A3644; border-radius: 4px; }
        .detail-text-col { flex: 1 1 480px; min-width: 320px; }
        .detail-text-col .markdown-block { font-size: 16px; }
      `,
      body,
      "ocr"
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

/// 一覧プレビュー用に先頭語義を取り出す（パース不能なら空文字）
function firstMeaningPreview(row: StoredWordRow): string {
  try {
    const info = JSON.parse(row.word_info_json) as WordInfo;
    return info.senses[0]?.meaning ?? "";
  } catch {
    return "";
  }
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
                <th>モデル</th><th>生成回数</th><th>作成日時</th><th>更新日時</th><th></th>
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

  const body = `
    <p><a href="/admin/words">← 一覧に戻る</a></p>
    <h1>単語 #${row.id}: ${escapeHtml(row.word)}</h1>
    <table class="meta-table">
      <tr><th>単語</th><td>${escapeHtml(row.word)}</td></tr>
      <tr><th>母語</th><td>${escapeHtml(row.target_language)}</td></tr>
      <tr><th>ユーザー訳語</th><td>${row.user_translation ? escapeHtml(row.user_translation) : "(なし)"}</td></tr>
      <tr><th>モデル</th><td>${escapeHtml(row.model)}</td></tr>
      <tr><th>生成回数</th><td>${row.generation_count}</td></tr>
      <tr><th>作成日時</th><td>${escapeHtml(formatSeattleTime(row.created_at))}</td></tr>
      <tr><th>更新日時</th><td>${escapeHtml(formatSeattleTime(row.updated_at))}</td></tr>
    </table>

    <div class="action-buttons">
      <form method="post" action="/admin/words/${row.id}/regenerate"
            onsubmit="return confirm('AI情報を再生成します。現在の内容は上書きされます。よろしいですか？')">
        <button type="submit" class="btn btn-primary">再生成する</button>
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
  if (model === "gemini-2.5-flash-preview-tts") usages.push("TTS (flash)");
  if (model === "gemini-2.5-pro-preview-tts") usages.push("TTS (pro)");
  if (model === ILLUSTRATION_MODEL) usages.push("単語イラスト");
  return usages.join(" / ");
}

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
          <tr><th>形式</th><th>問題</th><th>回答</th><th>モデル</th><th>コスト</th></tr>
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
