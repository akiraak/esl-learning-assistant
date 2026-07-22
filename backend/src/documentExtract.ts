import Anthropic from "@anthropic-ai/sdk";
import { PDFParse } from "pdf-parse";
import { PDFDocument } from "pdf-lib";
import mammoth from "mammoth";
import { config } from "./config";
import { callStructured, translateText } from "./ocrTranslate";

// PDF/DOCX のみを対象にする（レガシー .doc は非対象）。mediaType→保存拡張子の対応も兼ねる。
export const PDF_MEDIA_TYPE = "application/pdf";
export const DOCX_MEDIA_TYPE =
  "application/vnd.openxmlformats-officedocument.wordprocessingml.document";

export const SUPPORTED_DOCUMENT_MIME_EXTENSIONS: Record<string, string> = {
  [PDF_MEDIA_TYPE]: "pdf",
  [DOCX_MEDIA_TYPE]: "docx",
};

export function isSupportedDocumentMimeType(mediaType: unknown): mediaType is string {
  return typeof mediaType === "string" && mediaType in SUPPORTED_DOCUMENT_MIME_EXTENSIONS;
}

// PDF のテキスト層有無の判定しきい値。スキャンPDFはテキスト抽出結果が空〜数文字になるため、
// 空白を除いた文字数がこの値未満なら「テキスト層なし＝スキャン」とみなし OCR 経路へ回す。
// v1 はドキュメント単位の二択（ページごとの混在処理はしない。§2.2）。
export const MIN_TEXT_LAYER_CHARS = 16;

// 抽出テキストに実質的なテキスト層があるか（＝翻訳経路へ回せるか）を判定する。
// 空白を除いた文字数が MIN_TEXT_LAYER_CHARS 以上なら true（テキスト層あり）、
// 未満ならスキャンPDF とみなし false（OCR 経路へ）。
export function hasTextLayer(text: string): boolean {
  return text.replace(/\s/g, "").length >= MIN_TEXT_LAYER_CHARS;
}

// 文書インライン送信の上限（生バイト）。base64 は約1.33倍に膨らむため 14MB でも JSON ボディは
// ~18.7MB で express.json の 25mb 上限に収まり、この 400 ガードが 413 より先に働く。Claude の
// PDF document 上限（32MB/リクエスト）にも収まる。超過は「短い文書に分割」を促す（長尺は将来対応。§9.1）。
export const MAX_DOCUMENT_BYTES = 14 * 1024 * 1024;

// 文書1件ぶんの抽出/翻訳の出力上限。ESL の配布プリントは数ページ程度を想定し、英文＋訳が
// 収まる余裕を取る。これを超える長尺文書は末尾が切り詰められうる（将来: streaming＋分割。§9.1）。
const DOCUMENT_MAX_TOKENS = 16384;

// スキャンPDFのページ単位 OCR の出力上限。1ページぶんの原文＋訳は数千トークンに収まるため、
// 余裕を持たせつつ全ページ一括時代の 16384 切断（Unterminated string in JSON）を構造的に防ぐ。
const PDF_OCR_PAGE_MAX_TOKENS = 8192;

// ページ単位 OCR の同時実行数。多ページPDFの合計処理時間を抑えつつ、Claude API のレート制限に
// かかりにくい程度に留める（一時的な 429/overloaded は SDK 標準リトライに任せる）。
export const PDF_OCR_CONCURRENCY = 4;

// スキャンPDFの1ページを Claude に document ブロックで渡し、OCR＋翻訳を1回で行うスキーマ。
// ocrTranslate.ts の COMBINED_SCHEMA を画像→PDF文書に読み替えたもの。多ページPDFはページ分割して
// ページごとにこの呼び出しを行う（一括で送ると出力が max_tokens で切断され JSON が壊れるため）。
const DOCUMENT_OCR_SCHEMA = {
  type: "object",
  properties: {
    ocrText: {
      type: "string",
      description:
        "PDFページから文字起こしした英語の原文。Markdown形式で、見出しは#、箇条書きは-、" +
        "強調は**太字**/*斜体*など、原文のレイアウトが分かる記法を使うこと。本文が無いページは空文字列。",
    },
    translatedText: {
      type: "string",
      description:
        "ocrTextを目的言語に翻訳した文章。ocrTextと同じMarkdown構造（見出し・箇条書き・強調）を保つこと。",
    },
  },
  required: ["ocrText", "translatedText"],
  additionalProperties: false,
} as const;

export type DocumentExtractionMethod = "pdf-text" | "pdf-ocr" | "docx";

export interface DocumentExtractResult {
  extractedText: string;
  translatedText: string;
  extractionMethod: DocumentExtractionMethod;
  // AI 抽出（スキャンPDFの OCR）を使ったときのみモデル名が入る。テキスト抽出/DOCX は
  // ライブラリ抽出で AI 課金が無いため null（トークンも 0）。
  extractModel: string | null;
  extractInputTokens: number;
  extractOutputTokens: number;
  translateModel: string;
  translateInputTokens: number;
  translateOutputTokens: number;
}

// PDF のテキスト層をライブラリ抽出する。v2 の getText() は text にページ区切りの
// 「-- N of M --」マーカーを混ぜるため、pages 配列の text を自前で連結して混入を避ける。
export async function extractPdfText(fileBuffer: Buffer): Promise<string> {
  const parser = new PDFParse({ data: fileBuffer });
  try {
    const result = await parser.getText();
    return result.pages
      .map((page) => page.text.trim())
      .filter((text) => text.length > 0)
      .join("\n\n")
      .trim();
  } finally {
    await parser.destroy();
  }
}

// DOCX（.docx）のテキスト層を mammoth で抽出する。word/document.xml の段落テキストを
// 連結した結果を trim して返す（空なら "" ＝抽出不能）。ネットワーク・AI 課金は無い。
export async function extractDocxText(fileBuffer: Buffer): Promise<string> {
  const { value } = await mammoth.extractRawText({ buffer: fileBuffer });
  return value.trim();
}

// PDF を 1 ページずつの単一ページ PDF に分割する。スキャンPDFのページ単位 OCR 用。
// pdf-lib はテキスト層の有無に関係なくページ構造だけを複製するため、スキャン画像もそのまま保たれる。
export async function splitPdfIntoPages(fileBuffer: Buffer): Promise<Buffer[]> {
  // 取り込み PDF には印刷防止などの権限付き（暗号化扱い）のものがあるため ignoreEncryption で読む
  const source = await PDFDocument.load(fileBuffer, { ignoreEncryption: true });
  const pageCount = source.getPageCount();
  const pages: Buffer[] = [];
  for (let i = 0; i < pageCount; i++) {
    const single = await PDFDocument.create();
    const [page] = await single.copyPages(source, [i]);
    single.addPage(page);
    pages.push(Buffer.from(await single.save()));
  }
  return pages;
}

// items を最大 concurrency 並列で fn に通し、入力順のまま結果を返す。1件でも失敗すれば全体を reject
// （呼び出し側でリクエスト失敗として扱う）。ページ単位 OCR の並列実行用の小さなヘルパー。
export async function mapWithConcurrency<T, R>(
  items: T[],
  concurrency: number,
  fn: (item: T, index: number) => Promise<R>
): Promise<R[]> {
  const results = new Array<R>(items.length);
  let nextIndex = 0;
  const workers = Array.from({ length: Math.min(concurrency, items.length) }, async () => {
    while (nextIndex < items.length) {
      const index = nextIndex++;
      results[index] = await fn(items[index], index);
    }
  });
  await Promise.all(workers);
  return results;
}

// スキャンPDFの1ページを Claude の document ブロックで OCR＋翻訳する。
// 写真OCRの combinedOcrAndTranslate と同型で、image ブロックを document ブロックに置き換えたもの。
async function ocrAndTranslatePdfPage(pageBase64: string, targetLanguageCode: string) {
  const documentBlock: Anthropic.Messages.DocumentBlockParam = {
    type: "document",
    source: { type: "base64", media_type: "application/pdf", data: pageBase64 },
  };
  const { json, inputTokens, outputTokens } = await callStructured<{
    ocrText: string;
    translatedText: string;
  }>(
    config.ocrModel,
    DOCUMENT_OCR_SCHEMA,
    [
      documentBlock,
      {
        type: "text",
        text:
          `このPDFページ（テキスト層のないスキャン画像）から英語の本文をMarkdown形式で文字起こしし（ocrText）、` +
          `その文章を言語コード "${targetLanguageCode}" にMarkdown形式のまま翻訳してください（translatedText）。` +
          `見出し・箇条書き・強調（太字/斜体）など、原文のレイアウトが分かるようにMarkdown記法を使ってください。` +
          `本文の無いページは ocrText と translatedText を空文字列にしてください。`,
      },
    ],
    PDF_OCR_PAGE_MAX_TOKENS
  );
  return { ocrText: json.ocrText, translatedText: json.translatedText, inputTokens, outputTokens };
}

// スキャンPDF全体をページ分割し、ページごとの OCR＋翻訳を並列実行して結合する。
// 一括送信だと多ページで出力が max_tokens 切断され JSON が壊れる（本番で 13 ページ PDF が
// 「Unterminated string in JSON」で失敗）ため、ページ単位に分けて上限内に収める。
async function ocrAndTranslateScannedPdf(fileBuffer: Buffer, targetLanguageCode: string) {
  const pageBuffers = await splitPdfIntoPages(fileBuffer);
  const pageResults = await mapWithConcurrency(pageBuffers, PDF_OCR_CONCURRENCY, (pageBuffer) =>
    ocrAndTranslatePdfPage(pageBuffer.toString("base64"), targetLanguageCode)
  );

  const joinNonEmpty = (texts: string[]) =>
    texts.map((text) => text.trim()).filter((text) => text.length > 0).join("\n\n");
  return {
    ocrText: joinNonEmpty(pageResults.map((page) => page.ocrText)),
    translatedText: joinNonEmpty(pageResults.map((page) => page.translatedText)),
    inputTokens: pageResults.reduce((sum, page) => sum + page.inputTokens, 0),
    outputTokens: pageResults.reduce((sum, page) => sum + page.outputTokens, 0),
  };
}

/// 文書（PDF/DOCX）を抽出＋翻訳する。ハイブリッド:
/// - DOCX: mammoth でテキスト抽出 → 既存 translateText で翻訳
/// - PDF（テキスト層あり）: pdf-parse で抽出 → translateText
/// - PDF（テキスト層なし＝スキャン）: ページ分割し Claude の document ブロックでページ単位に OCR＋翻訳
export async function extractAndTranslateDocument(
  fileBuffer: Buffer,
  mediaType: string,
  targetLanguageCode: string
): Promise<DocumentExtractResult> {
  if (mediaType === DOCX_MEDIA_TYPE) {
    const extractedText = await extractDocxText(fileBuffer);
    if (!extractedText) {
      throw new Error("no extractable text in document");
    }
    const translation = await translateText(extractedText, targetLanguageCode, DOCUMENT_MAX_TOKENS);
    return {
      extractedText,
      translatedText: translation.text,
      extractionMethod: "docx",
      extractModel: null,
      extractInputTokens: 0,
      extractOutputTokens: 0,
      translateModel: config.translateModel,
      translateInputTokens: translation.inputTokens,
      translateOutputTokens: translation.outputTokens,
    };
  }

  // PDF: まずテキスト層を抽出し、実質空ならスキャンとみなして OCR 経路へ。
  const pdfText = await extractPdfText(fileBuffer);

  if (hasTextLayer(pdfText)) {
    const translation = await translateText(pdfText, targetLanguageCode, DOCUMENT_MAX_TOKENS);
    return {
      extractedText: pdfText,
      translatedText: translation.text,
      extractionMethod: "pdf-text",
      extractModel: null,
      extractInputTokens: 0,
      extractOutputTokens: 0,
      translateModel: config.translateModel,
      translateInputTokens: translation.inputTokens,
      translateOutputTokens: translation.outputTokens,
    };
  }

  // テキスト層なし（スキャン）: ページ分割して Claude でページ単位に OCR＋翻訳。
  const ocr = await ocrAndTranslateScannedPdf(fileBuffer, targetLanguageCode);
  return {
    extractedText: ocr.ocrText,
    translatedText: ocr.translatedText,
    extractionMethod: "pdf-ocr",
    extractModel: config.ocrModel,
    extractInputTokens: ocr.inputTokens,
    extractOutputTokens: ocr.outputTokens,
    // OCR と翻訳を1回の呼び出しにまとめたため翻訳ぶんの別課金は無い（combinedOcrAndTranslate と同じ扱い）。
    translateModel: config.translateModel,
    translateInputTokens: 0,
    translateOutputTokens: 0,
  };
}

// /api/document-extract-translate の送信前バリデーション。fileBase64 必須・mediaType ホワイトリスト・
// targetLanguage 必須・base64 デコード後 0 バイト拒否・サイズ上限（MAX_DOCUMENT_BYTES）をこの順で検査し、
// 成否と（成功時は）後続処理に必要な値を返す。すべての失敗は HTTP 400 相当（呼び出し側が status を付ける）。
export interface DocumentExtractRequestFields {
  fileBuffer: Buffer;
  mediaType: string;
  fileKind: string;
  targetLanguage: string;
  /// アプリ側の表示名（Document.title）。任意。管理画面のコンテンツファイル一覧での突き合わせ用
  title: string | null;
}

export type DocumentExtractRequestValidation =
  | { ok: true; value: DocumentExtractRequestFields }
  | { ok: false; error: string };

export function validateDocumentExtractRequest(body: unknown): DocumentExtractRequestValidation {
  const { fileBase64, mediaType, targetLanguage, title } = (body ?? {}) as {
    fileBase64?: unknown;
    mediaType?: unknown;
    targetLanguage?: unknown;
    title?: unknown;
  };

  if (typeof fileBase64 !== "string" || !fileBase64) {
    return { ok: false, error: "fileBase64 is required" };
  }
  if (!isSupportedDocumentMimeType(mediaType)) {
    return {
      ok: false,
      error: `mediaType must be one of: ${Object.keys(SUPPORTED_DOCUMENT_MIME_EXTENSIONS).join(", ")}`,
    };
  }
  if (typeof targetLanguage !== "string" || !targetLanguage) {
    return { ok: false, error: "targetLanguage is required" };
  }
  if (title !== undefined && typeof title !== "string") {
    return { ok: false, error: "title must be a string" };
  }

  const fileBuffer = Buffer.from(fileBase64, "base64");
  if (fileBuffer.length === 0) {
    return { ok: false, error: "fileBase64 is not valid base64 document data" };
  }
  if (fileBuffer.length > MAX_DOCUMENT_BYTES) {
    return {
      ok: false,
      error: `document too large (${(fileBuffer.length / 1024 / 1024).toFixed(1)}MB, max ${MAX_DOCUMENT_BYTES / 1024 / 1024}MB). split into shorter documents`,
    };
  }

  return {
    ok: true,
    value: {
      fileBuffer,
      mediaType,
      fileKind: SUPPORTED_DOCUMENT_MIME_EXTENSIONS[mediaType],
      targetLanguage,
      title: typeof title === "string" && title.trim() ? title.trim().slice(0, 200) : null,
    },
  };
}
