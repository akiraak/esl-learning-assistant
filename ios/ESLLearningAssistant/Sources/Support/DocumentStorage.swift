import Foundation

/// 取り込んだ文書（Document, PDF/DOCX）の原本置き場。AudioStorage と同じ作法で
/// Documents/Documents に `UUID.ext` で保存する。実ファイルの生成・参照・削除を担う。
/// 保存（`save`）は Phase 3 の取り込みで使う。Phase 1 では削除系（`delete`/`deleteAll`）を
/// `ModelContext.deleteDocument` / `DebugDataCleaner` が参照する。
enum DocumentStorage {
    private static var directoryURL: URL {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Documents", isDirectory: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }

    /// 文書データを保存してファイル名（`UUID.ext`）を返す。ビューア（PDFView/QuickLook）が
    /// 種別を判別できるよう元の拡張子を保つ（空なら拡張子なし）。
    static func save(data: Data, ext: String) -> String? {
        let cleanExt = ext.lowercased()
        let fileName = cleanExt.isEmpty ? UUID().uuidString : "\(UUID().uuidString).\(cleanExt)"
        let fileURL = directoryURL.appendingPathComponent(fileName)
        do {
            try data.write(to: fileURL, options: .atomic)
            return fileName
        } catch {
            return nil
        }
    }

    static func url(fileName: String) -> URL {
        directoryURL.appendingPathComponent(fileName)
    }

    static func exists(fileName: String) -> Bool {
        FileManager.default.fileExists(atPath: url(fileName: fileName).path)
    }

    static func delete(fileName: String) {
        try? FileManager.default.removeItem(at: url(fileName: fileName))
    }

    /// Documents/Documents ディレクトリごと削除する（次回saveで再作成される）。全データ削除用。
    static func deleteAll() {
        try? FileManager.default.removeItem(at: directoryURL)
    }
}
