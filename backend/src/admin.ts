import path from "path";
import { Router } from "express";
import { marked } from "marked";
import fs from "fs";
import {
  deleteStoredWord,
  deleteTtsAudio,
  getRequestLog,
  getStoredWordById,
  getTtsAudioById,
  getWordInfoLog,
  insertWordInfoLog,
  listRecentRequestLogs,
  listRecentSystemLogs,
  listRecentWordInfoLogs,
  listStoredWords,
  listTtsAudio,
  RequestLogRow,
  StoredWordRow,
  upsertStoredWord,
  WordInfoLogRow,
} from "./db";
import { config } from "./config";
import { generateWordInfo, type WordInfo } from "./wordInfo";
import { estimateCostUsd } from "./pricing";
import { logger } from "./logger";

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

function statusLabel(log: { status: string }): string {
  const cls = log.status === "success" ? "status-success" : "status-error";
  return `<span class="${cls}">${escapeHtml(log.status)}</span>`;
}

function navLinks(active: "ocr" | "word-info" | "words" | "tts" | "logs"): string {
  const ocr = active === "ocr" ? "<strong>OCR・翻訳ログ</strong>" : `<a href="/admin">OCR・翻訳ログ</a>`;
  const wordInfo =
    active === "word-info" ? "<strong>単語情報ログ</strong>" : `<a href="/admin/word-info">単語情報ログ</a>`;
  const words = active === "words" ? "<strong>単語一覧</strong>" : `<a href="/admin/words">単語一覧</a>`;
  const tts = active === "tts" ? "<strong>TTS一覧</strong>" : `<a href="/admin/tts">TTS一覧</a>`;
  const logs = active === "logs" ? "<strong>システムログ</strong>" : `<a href="/admin/system-logs">システムログ</a>`;
  return `<p>${ocr} | ${wordInfo} | ${words} | ${tts} | ${logs}</p>`;
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
          <td>${escapeHtml(formatSeattleTime(log.created_at))}</td>
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
        ${navLinks("ocr")}
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

adminRouter.get("/word-info", (_req, res) => {
  const logs = listRecentWordInfoLogs(100);

  const rows = logs
    .map(
      (log) => `
        <tr class="log-row">
          <td>${log.id}</td>
          <td>${escapeHtml(formatSeattleTime(log.created_at))}</td>
          <td><strong>${escapeHtml(log.word)}</strong>${
            log.user_translation ? `<br><span style="color:#666">${escapeHtml(log.user_translation)}</span>` : ""
          }</td>
          <td>${escapeHtml(log.target_language)}</td>
          <td>${log.context ? "あり" : "なし"}</td>
          <td>${log.cache_hit ? '<span style="color:#2a7">キャッシュ返却</span><br>' : ""}${escapeHtml(log.model)} (in:${log.input_tokens} / out:${log.output_tokens})</td>
          <td>$${log.cost_usd.toFixed(5)}</td>
          <td>${statusLabel(log)}${log.error_message ? `<br>${escapeHtml(log.error_message)}` : ""}</td>
          <td>${log.latency_ms}ms</td>
          <td><a href="/admin/word-info/${log.id}">詳細を見る →</a></td>
        </tr>
      `
    )
    .join("\n");

  res.type("html").send(
    renderPage(
      "ESL Learning Assistant - 単語情報ログ",
      "",
      `
        <h1>単語情報生成ログ</h1>
        ${navLinks("word-info")}
        <p>直近${logs.length}件</p>
        <table>
          <thead>
            <tr>
              <th>ID</th><th>日時</th><th>単語</th><th>母語</th><th>文脈</th>
              <th>モデル/トークン数</th><th>コスト</th><th>状態</th><th>処理時間</th><th></th>
            </tr>
          </thead>
          <tbody>${rows}</tbody>
        </table>
      `
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
          <td>${i + 1}</td>
          <td>${escapeHtml(sense.partOfSpeech)}</td>
          <td>${escapeHtml(sense.meaning)}</td>
          <td>${escapeHtml(sense.englishDefinition)}</td>
          <td>${sense.note ? escapeHtml(sense.note) : ""}</td>
        </tr>
      `
    )
    .join("\n");

  const examples = info.examples
    .map((ex) => `<li>${escapeHtml(ex.english)}<br><span style="color:#666">${escapeHtml(ex.translation)}</span></li>`)
    .join("\n");

  const inflections = info.inflections
    .map((inf) => `${escapeHtml(inf.form)}: ${escapeHtml(inf.text)}`)
    .join(" / ");

  const optionalRow = (label: string, value: string | null) =>
    value ? `<tr><th>${label}</th><td>${escapeHtml(value)}</td></tr>` : "";

  return `
    <h2>語義</h2>
    <table>
      <thead><tr><th>#</th><th>品詞</th><th>意味</th><th>英語定義</th><th>ニュアンス</th></tr></thead>
      <tbody>${senses}</tbody>
    </table>
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

  res.type("html").send(
    renderPage(
      `単語情報ログ #${log.id} - ESL Learning Assistant`,
      `
        .meta-table { border-collapse: collapse; margin: 12px 0 24px; width: auto; }
        .meta-table th, .meta-table td { border: 1px solid #ccc; padding: 6px 12px; font-size: 13px; text-align: left; }
        .meta-table th { background: #f0f0f0; white-space: nowrap; }
        .markdown-block {
          font-size: 14px;
          line-height: 1.7;
          border: 1px solid #ddd;
          border-radius: 6px;
          padding: 16px 20px;
          margin-bottom: 24px;
          background: #fafafa;
        }
        pre { background: #f5f5f5; padding: 12px; border-radius: 6px; overflow-x: auto; }
        .nav-links { margin-top: 16px; }
      `,
      body
    )
  );
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
          <td>${row.id}</td>
          <td><strong>${escapeHtml(row.word)}</strong></td>
          <td>${escapeHtml(row.target_language)}</td>
          <td>${escapeHtml(firstMeaningPreview(row))}</td>
          <td>${escapeHtml(row.model)}</td>
          <td>${row.generation_count}</td>
          <td>${escapeHtml(formatSeattleTime(row.created_at))}</td>
          <td>${escapeHtml(formatSeattleTime(row.updated_at))}</td>
          <td><a href="/admin/words/${row.id}">詳細を見る →</a></td>
        </tr>
      `
    )
    .join("\n");

  res.type("html").send(
    renderPage(
      "ESL Learning Assistant - 単語一覧",
      "",
      `
        <h1>保存済み単語一覧</h1>
        ${navLinks("words")}
        <p>全${words.length}件</p>
        <table>
          <thead>
            <tr>
              <th>ID</th><th>単語</th><th>母語</th><th>先頭語義</th>
              <th>モデル</th><th>生成回数</th><th>作成日時</th><th>更新日時</th><th></th>
            </tr>
          </thead>
          <tbody>${rows}</tbody>
        </table>
      `
    )
  );
});

const WORD_DETAIL_STYLE = `
  .meta-table { border-collapse: collapse; margin: 12px 0 24px; width: auto; }
  .meta-table th, .meta-table td { border: 1px solid #ccc; padding: 6px 12px; font-size: 13px; text-align: left; }
  .meta-table th { background: #f0f0f0; white-space: nowrap; }
  .markdown-block {
    font-size: 14px;
    line-height: 1.7;
    border: 1px solid #ddd;
    border-radius: 6px;
    padding: 16px 20px;
    margin-bottom: 24px;
    background: #fafafa;
  }
  pre { background: #f5f5f5; padding: 12px; border-radius: 6px; overflow-x: auto; }
  .action-buttons { display: flex; gap: 12px; margin: 16px 0 24px; }
  .action-buttons button { padding: 8px 16px; font-size: 14px; cursor: pointer; }
  .danger-button { color: #c33; }
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
        <button type="submit">再生成する</button>
      </form>
      <form method="post" action="/admin/words/${row.id}/delete"
            onsubmit="return confirm('この単語の保存データを削除します。よろしいですか？（アプリから再リクエストされれば再生成されます）')">
        <button type="submit" class="danger-button">削除する</button>
      </form>
    </div>

    ${renderWordInfoBlock(row)}

    <h2>文脈（最後の生成に使用）</h2>
    ${row.context ? `<div class="markdown-block">${renderMarkdown(row.context)}</div>` : "<p>(なし)</p>"}
  `;

  res.type("html").send(renderPage(`単語 #${row.id}: ${row.word} - ESL Learning Assistant`, WORD_DETAIL_STYLE, body));
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

  const tableRows = rows
    .map((row) => {
      const preview = row.text.length > 80 ? `${row.text.slice(0, 80)}…` : row.text;
      const cost = hasCostRecord(row) ? `$${row.cost_usd.toFixed(4)}` : "—";
      return `
        <tr class="log-row">
          <td>${row.id}</td>
          <td>${escapeHtml(formatSeattleTime(row.created_at))}</td>
          <td>${escapeHtml(preview)}</td>
          <td>${escapeHtml(row.voice)}</td>
          <td>${escapeHtml(row.model)}</td>
          <td>${(row.byte_size / 1024).toFixed(0)} KB</td>
          <td>${formatTtsDuration(row.byte_size)}</td>
          <td>${cost}</td>
          <td><audio controls preload="none" src="/admin/tts/${row.id}/audio" style="width:220px;height:32px;"></audio></td>
          <td>
            <form method="post" action="/admin/tts/${row.id}/delete"
                  onsubmit="return confirm('このTTS音声を削除します。よろしいですか？（同じテキストが再生されれば再合成されます）')">
              <button type="submit" style="color:#c33;cursor:pointer;">削除</button>
            </form>
          </td>
        </tr>
      `;
    })
    .join("\n");

  res.type("html").send(
    renderPage(
      "ESL Learning Assistant - TTS一覧",
      "",
      `
        <h1>保存済みTTS音声一覧</h1>
        ${navLinks("tts")}
        <p>全${rows.length}件 ／ 料金合計 $${totalCostUsd.toFixed(4)}（トークン記録のある行のみの合算）</p>
        <table>
          <thead>
            <tr>
              <th>ID</th><th>作成日時</th><th>テキスト</th><th>声</th><th>モデル</th>
              <th>サイズ</th><th>長さ</th><th>料金</th><th>試聴</th><th></th>
            </tr>
          </thead>
          <tbody>${tableRows}</tbody>
        </table>
      `
    )
  );
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
          <td>${log.id}</td>
          <td>${escapeHtml(formatSeattleTime(log.created_at))}</td>
          <td>${escapeHtml(log.category)}</td>
          <td>${escapeHtml(log.level)}</td>
          <td>${escapeHtml(log.message)}</td>
        </tr>
      `;
    })
    .join("\n");

  res.type("html").send(
    renderPage(
      "ESL Learning Assistant - システムログ",
      `
        .level-warn td { color: #96700a; }
        .level-error td { color: #c33; }
      `,
      `
        <h1>システムログ</h1>
        ${navLinks("logs")}
        <p>直近${logs.length}件</p>
        <table>
          <thead>
            <tr>
              <th>ID</th><th>日時</th><th>カテゴリ</th><th>レベル</th><th>メッセージ</th>
            </tr>
          </thead>
          <tbody>${rows}</tbody>
        </table>
      `
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
