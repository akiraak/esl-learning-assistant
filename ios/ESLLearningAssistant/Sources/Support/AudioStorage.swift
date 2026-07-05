import Foundation

/// 取り込んだ音声（AudioClip）のバイナリ置き場。PhotoStorage と同じ作法で
/// Documents/Audio に `UUID.ext` で保存する。実ファイルの生成・参照・削除を担う。
enum AudioStorage {
    private static var directoryURL: URL {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Audio", isDirectory: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }

    /// 音声データを保存してファイル名（`UUID.ext`）を返す。拡張子は AVAudioPlayer が
    /// フォーマットを判別できるよう元のものを保つ（空なら拡張子なし）。
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

    /// Audioディレクトリごと削除する（次回saveで再作成される）。全データ削除用。
    static func deleteAll() {
        try? FileManager.default.removeItem(at: directoryURL)
    }
}
