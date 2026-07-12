import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import {
  PDF_MEDIA_TYPE,
  DOCX_MEDIA_TYPE,
  SUPPORTED_DOCUMENT_MIME_EXTENSIONS,
  isSupportedDocumentMimeType,
  hasTextLayer,
  MIN_TEXT_LAYER_CHARS,
  MAX_DOCUMENT_BYTES,
  validateDocumentExtractRequest,
  extractPdfText,
  extractDocxText,
  extractAndTranslateDocument,
} from "../src/documentExtract";

// documentExtract の import はネットワーク/DB/ファイル書き込みの副作用を持たない
// （ocrTranslate は Anthropic クライアントを構築するだけで通信しない）。ここでは AI を叩かない
// 純粋関数・ライブラリ抽出・送信前バリデーションのみを対象にする（スキャンOCR/翻訳は Phase 2 の
// 実 Claude 疎通で確認済み）。

const fixture = (name: string) => fs.readFileSync(path.join(__dirname, "fixtures", name));

// --- mediaType ホワイトリスト -------------------------------------------------

test("isSupportedDocumentMimeType: PDF/DOCX の mediaType のみ受理する", () => {
  assert.equal(isSupportedDocumentMimeType(PDF_MEDIA_TYPE), true);
  assert.equal(isSupportedDocumentMimeType(DOCX_MEDIA_TYPE), true);
  assert.equal(isSupportedDocumentMimeType("application/msword"), false); // レガシー .doc は非対象
  assert.equal(isSupportedDocumentMimeType("text/plain"), false);
  assert.equal(isSupportedDocumentMimeType(""), false);
  assert.equal(isSupportedDocumentMimeType(undefined), false);
  assert.equal(isSupportedDocumentMimeType(null), false);
  assert.equal(isSupportedDocumentMimeType(123), false);
});

test("SUPPORTED_DOCUMENT_MIME_EXTENSIONS: mediaType→保存拡張子の対応", () => {
  assert.equal(SUPPORTED_DOCUMENT_MIME_EXTENSIONS[PDF_MEDIA_TYPE], "pdf");
  assert.equal(SUPPORTED_DOCUMENT_MIME_EXTENSIONS[DOCX_MEDIA_TYPE], "docx");
  assert.deepEqual(Object.keys(SUPPORTED_DOCUMENT_MIME_EXTENSIONS), [PDF_MEDIA_TYPE, DOCX_MEDIA_TYPE]);
});

// --- テキスト層判定（テキスト抽出 vs スキャンOCR の分岐） ----------------------

test("hasTextLayer: 空白を除いた文字数が MIN_TEXT_LAYER_CHARS 以上なら true", () => {
  assert.equal(MIN_TEXT_LAYER_CHARS, 16);
  // ちょうど 15 文字（境界の1つ下）は false
  assert.equal(hasTextLayer("a".repeat(15)), false);
  // ちょうど 16 文字（境界）は true
  assert.equal(hasTextLayer("a".repeat(16)), true);
  assert.equal(hasTextLayer("a".repeat(17)), true);
});

test("hasTextLayer: 空・空白のみはテキスト層なし（スキャン扱い）", () => {
  assert.equal(hasTextLayer(""), false);
  assert.equal(hasTextLayer("   \n\t  \r\n "), false);
  // 空白は数えないので、非空白が 16 未満なら大量の空白があっても false
  assert.equal(hasTextLayer("  a  b  c  \n\n  d  "), false);
});

// --- 送信前バリデーション（/api/document-extract-translate） -------------------

test("validateDocumentExtractRequest: fileBase64 必須", () => {
  for (const body of [{}, { fileBase64: "" }, { fileBase64: 123 }, { fileBase64: null }, null, undefined]) {
    const r = validateDocumentExtractRequest(body);
    assert.equal(r.ok, false);
    assert.equal(r.ok === false && r.error, "fileBase64 is required");
  }
});

test("validateDocumentExtractRequest: mediaType はホワイトリスト", () => {
  const r = validateDocumentExtractRequest({ fileBase64: "aGVsbG8=", mediaType: "application/msword" });
  assert.equal(r.ok, false);
  assert.equal(
    r.ok === false && r.error,
    `mediaType must be one of: ${PDF_MEDIA_TYPE}, ${DOCX_MEDIA_TYPE}`
  );
});

test("validateDocumentExtractRequest: targetLanguage 必須", () => {
  const r = validateDocumentExtractRequest({ fileBase64: "aGVsbG8=", mediaType: PDF_MEDIA_TYPE });
  assert.equal(r.ok, false);
  assert.equal(r.ok === false && r.error, "targetLanguage is required");
});

test("validateDocumentExtractRequest: base64 デコード後 0 バイトを拒否", () => {
  // "!" は base64 の文字集合外で、Buffer.from(..., 'base64') は無視して 0 バイトになる。
  const r = validateDocumentExtractRequest({
    fileBase64: "!",
    mediaType: PDF_MEDIA_TYPE,
    targetLanguage: "ja",
  });
  assert.equal(r.ok, false);
  assert.equal(r.ok === false && r.error, "fileBase64 is not valid base64 document data");
});

test("validateDocumentExtractRequest: サイズ上限（MAX_DOCUMENT_BYTES）超過を拒否", () => {
  const tooBig = Buffer.alloc(MAX_DOCUMENT_BYTES + 1).toString("base64");
  const r = validateDocumentExtractRequest({
    fileBase64: tooBig,
    mediaType: PDF_MEDIA_TYPE,
    targetLanguage: "ja",
  });
  assert.equal(r.ok, false);
  assert.match(r.ok === false ? r.error : "", /^document too large \(14\.0MB, max 14MB\)\. split into shorter documents$/);
});

test("validateDocumentExtractRequest: 上限ちょうどは受理", () => {
  const atLimit = Buffer.alloc(MAX_DOCUMENT_BYTES).toString("base64");
  const r = validateDocumentExtractRequest({
    fileBase64: atLimit,
    mediaType: DOCX_MEDIA_TYPE,
    targetLanguage: "ja",
  });
  assert.equal(r.ok, true);
});

test("validateDocumentExtractRequest: 正常系は後続処理に必要な値を返す", () => {
  const buf = Buffer.from("%PDF-1.4 hello");
  const r = validateDocumentExtractRequest({
    fileBase64: buf.toString("base64"),
    mediaType: PDF_MEDIA_TYPE,
    targetLanguage: "ja",
  });
  assert.equal(r.ok, true);
  if (r.ok) {
    assert.equal(r.value.mediaType, PDF_MEDIA_TYPE);
    assert.equal(r.value.fileKind, "pdf");
    assert.equal(r.value.targetLanguage, "ja");
    assert.deepEqual(r.value.fileBuffer, buf);
    assert.equal(r.value.title, null);
  }
});

test("validateDocumentExtractRequest: title は任意（trim して受理、空や未指定は null、string 以外は拒否）", () => {
  const base = {
    fileBase64: Buffer.from("%PDF-1.4 hello").toString("base64"),
    mediaType: PDF_MEDIA_TYPE,
    targetLanguage: "ja",
  };

  const withTitle = validateDocumentExtractRequest({ ...base, title: "  英語教材.pdf  " });
  assert.equal(withTitle.ok, true);
  if (withTitle.ok) assert.equal(withTitle.value.title, "英語教材.pdf");

  const emptyTitle = validateDocumentExtractRequest({ ...base, title: "   " });
  assert.equal(emptyTitle.ok, true);
  if (emptyTitle.ok) assert.equal(emptyTitle.value.title, null);

  const longTitle = validateDocumentExtractRequest({ ...base, title: "a".repeat(300) });
  assert.equal(longTitle.ok, true);
  if (longTitle.ok) assert.equal(longTitle.value.title?.length, 200);

  const badTitle = validateDocumentExtractRequest({ ...base, title: 123 });
  assert.equal(badTitle.ok, false);
  if (!badTitle.ok) assert.match(badTitle.error, /title/);
});

// --- 抽出（ライブラリ経路・AI 不使用） ---------------------------------------

test("extractPdfText: テキスト層のある PDF から本文を抽出する（pdf-text 経路）", async () => {
  const text = await extractPdfText(fixture("text-layer.pdf"));
  assert.match(text, /text-layer PDF fixture/);
  assert.equal(hasTextLayer(text), true);
});

test("extractPdfText: テキスト層のない PDF は実質空を返す（pdf-ocr 経路へ回る）", async () => {
  const text = await extractPdfText(fixture("scanned.pdf"));
  assert.equal(hasTextLayer(text), false);
});

test("extractDocxText: DOCX の本文段落を抽出する（docx 経路）", async () => {
  const text = await extractDocxText(fixture("sample.docx"));
  assert.match(text, /Hello from the DOCX fixture\./);
  assert.match(text, /plain text layer for extraction tests\./);
});

test("extractDocxText: 本文が空の DOCX は空文字を返す", async () => {
  const text = await extractDocxText(fixture("empty.docx"));
  assert.equal(text, "");
});

// --- オーケストレータの AI 不要な分岐（DOCX 抽出不能 → 例外） -----------------

test("extractAndTranslateDocument: 抽出テキストが空の DOCX は翻訳前に例外を投げる", async () => {
  await assert.rejects(
    () => extractAndTranslateDocument(fixture("empty.docx"), DOCX_MEDIA_TYPE, "ja"),
    /no extractable text in document/
  );
});
