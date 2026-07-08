// テスト用の文書 fixture を生成する再現用スクリプト（コミット済みの成果物とペア）。
//   node test/fixtures/generate.js
// で以下を再生成する:
//   - text-layer.pdf : テキスト層のある PDF（pdf-parse で本文が取れる ＝ "pdf-text" 経路）
//   - scanned.pdf    : テキスト層のない PDF（本文が取れない ＝ "pdf-ocr" 経路へ回る判定用）
//   - sample.docx    : mammoth で抽出できる最小 DOCX（"docx" 経路）
//   - empty.docx     : 本文が空の DOCX（抽出結果 "" ＝ "no extractable text" 例外の検証用）
// 依存を増やさないため、PDF は手組みバイト列、DOCX は `zip` CLI で OOXML を固める。
const fs = require("fs");
const path = require("path");
const os = require("os");
const { execFileSync } = require("child_process");

const OUT_DIR = __dirname;

// --- PDF: オブジェクトを xref オフセット付きで手組みする最小 PDF ---
function buildPdf(contentStream) {
  const header = "%PDF-1.4\n";
  const objects = [
    "<< /Type /Catalog /Pages 2 0 R >>",
    "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] " +
      "/Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>",
    "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    `<< /Length ${Buffer.byteLength(contentStream, "utf8")} >>\nstream\n${contentStream}\nendstream`,
  ];

  let body = header;
  const offsets = [];
  objects.forEach((obj, i) => {
    offsets.push(Buffer.byteLength(body, "utf8"));
    body += `${i + 1} 0 obj\n${obj}\nendobj\n`;
  });

  const xrefOffset = Buffer.byteLength(body, "utf8");
  let xref = `xref\n0 ${objects.length + 1}\n0000000000 65535 f \n`;
  for (const off of offsets) {
    xref += `${String(off).padStart(10, "0")} 00000 n \n`;
  }
  const trailer =
    `trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n` +
    `startxref\n${xrefOffset}\n%%EOF\n`;

  return Buffer.from(body + xref + trailer, "utf8");
}

const textLayerContent =
  "BT /F1 18 Tf 72 720 Td (Hello from the text-layer PDF fixture.) Tj\n" +
  "0 -24 Td (This PDF carries a real text layer for extraction tests.) Tj ET";
// テキスト描画命令を含まない空ページ ＝ pdf-parse は本文を取れない（スキャン相当）。
const scannedContent = "BT ET";

fs.writeFileSync(path.join(OUT_DIR, "text-layer.pdf"), buildPdf(textLayerContent));
fs.writeFileSync(path.join(OUT_DIR, "scanned.pdf"), buildPdf(scannedContent));

// --- DOCX: 最小 OOXML パッケージを zip で固める ---
const CONTENT_TYPES = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
</Types>`;

const RELS = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>`;

const DOCUMENT_XML = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    <w:p><w:r><w:t>Hello from the DOCX fixture.</w:t></w:r></w:p>
    <w:p><w:r><w:t>This document has a plain text layer for extraction tests.</w:t></w:r></w:p>
  </w:body>
</w:document>`;

const EMPTY_DOCUMENT_XML = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body><w:p/></w:body>
</w:document>`;

function buildDocx(documentXml, outName) {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "docx-fixture-"));
  fs.writeFileSync(path.join(tmp, "[Content_Types].xml"), CONTENT_TYPES);
  fs.mkdirSync(path.join(tmp, "_rels"));
  fs.writeFileSync(path.join(tmp, "_rels", ".rels"), RELS);
  fs.mkdirSync(path.join(tmp, "word"));
  fs.writeFileSync(path.join(tmp, "word", "document.xml"), documentXml);

  const outPath = path.join(OUT_DIR, outName);
  fs.rmSync(outPath, { force: true });
  execFileSync("zip", ["-X", "-r", "-q", outPath, "[Content_Types].xml", "_rels", "word"], {
    cwd: tmp,
  });
  fs.rmSync(tmp, { recursive: true, force: true });
}

buildDocx(DOCUMENT_XML, "sample.docx");
buildDocx(EMPTY_DOCUMENT_XML, "empty.docx");

console.log("fixtures written:", fs.readdirSync(OUT_DIR).filter((f) => f !== "generate.js").sort().join(", "));
