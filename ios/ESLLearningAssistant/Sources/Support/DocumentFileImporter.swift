import Foundation
import SwiftData

/// `DocumentKind`（pdf/docx）と、取り込み拡張子・送信 mediaType の対応。
/// 取り込み（`DocumentFileImporter`）と送信（`RemoteDocumentExtractTranslateService`）の
/// 両方が参照するため一箇所にまとめる。mediaType は backend の
/// `SUPPORTED_DOCUMENT_MIME_EXTENSIONS`（`documentExtract.ts`）と一致させること。
extension DocumentKind {
    /// 取り込みファイルの拡張子から種別を判定する（未対応拡張子は nil）。
    init?(fileExtension ext: String) {
        switch ext.lowercased() {
        case "pdf": self = .pdf
        case "docx": self = .docx
        default: return nil
        }
    }

    /// 保存ファイル名に付ける拡張子（ビューアが種別を判別できるよう保つ）。
    var fileExtension: String {
        switch self {
        case .pdf: "pdf"
        case .docx: "docx"
        }
    }

    /// backend へ送る mediaType。
    var mediaType: String {
        switch self {
        case .pdf: "application/pdf"
        case .docx: "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        }
    }
}

/// iOS の「ファイル」ピッカー（.fileImporter / UIDocumentPicker）で選ばれた文書URL（PDF/DOCX）を
/// アプリに取り込み、`Document` 化する共通処理。iCloud・端末内など Files に見える場所すべてから
/// 取り込める。音声の `AudioFileImporter` の文書版。
enum DocumentFileImporter {
    /// 選択されたファイルURL群を取り込み、作成した文書数を返す。
    /// ドキュメントピッカーのURLはセキュリティスコープ付きなので明示的にアクセス開始/終了する。
    /// 未対応拡張子（pdf/docx 以外）や読み込み失敗は黙ってスキップする。
    /// レッスンはライブラリ型のため任意（`nil` で 0 個紐付けのライブラリ文書になる）。
    @discardableResult
    static func importFiles(_ urls: [URL], into lesson: Lesson?, context: ModelContext) -> Int {
        var count = 0
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }

            guard let kind = DocumentKind(fileExtension: url.pathExtension) else { continue }
            guard let data = try? Data(contentsOf: url) else { continue }
            guard let fileName = DocumentStorage.save(data: data, ext: kind.fileExtension) else { continue }

            let title = url.deletingPathExtension().lastPathComponent
            let document = Document(
                title: title.isEmpty ? url.lastPathComponent : title,
                documentFileName: fileName,
                fileKind: kind,
                sourcePath: nil,
                byteSize: data.count,
                lessons: lesson.map { [$0] } ?? []
            )
            context.insert(document)
            count += 1
        }
        if count > 0 {
            context.saveOrLog()
        }
        return count
    }
}
