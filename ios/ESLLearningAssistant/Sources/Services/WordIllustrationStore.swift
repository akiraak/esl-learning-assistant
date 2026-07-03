import CryptoKit
import Foundation

/// サーバで生成した単語イラスト（PNG）の端末ローカル置き場を管理する。
/// 「生成済み＝即表示」の状態を画面再訪やオフライン時にも維持するため、
/// OSに消されうる Caches ではなく Application Support 配下に保存する。
/// キーはサーバ側（word_illustrations.key_hash）と同じ
/// sha256("model|word|target_language|sense_index")。word はサーバ側の正規化
/// （trim + 小文字化）に合わせる。
enum WordIllustrationStore {
    /// サーバ側 illustration.ts の ILLUSTRATION_MODEL と合わせる
    static let model = "gpt-image-2"

    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("illustrations", isDirectory: true)
    }

    static func key(word: String, targetLanguage: String, senseIndex: Int = 0) -> String {
        let normalizedWord = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let digest = SHA256.hash(data: Data("\(model)|\(normalizedWord)|\(targetLanguage)|\(senseIndex)".utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// 保存済みならファイルURLを返す（未生成なら nil）
    static func localURL(word: String, targetLanguage: String, senseIndex: Int = 0) -> URL? {
        let url = fileURL(word: word, targetLanguage: targetLanguage, senseIndex: senseIndex)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// 画像データを保存してファイルURLを返す
    @discardableResult
    static func save(data: Data, word: String, targetLanguage: String, senseIndex: Int = 0) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = fileURL(word: word, targetLanguage: targetLanguage, senseIndex: senseIndex)
        try data.write(to: url, options: .atomic)
        return url
    }

    /// 保存済みイラストを全削除する（Settingsのデバッグメニュー等からの利用を想定）
    static func removeAll() {
        try? FileManager.default.removeItem(at: directory)
    }

    private static func fileURL(word: String, targetLanguage: String, senseIndex: Int) -> URL {
        directory.appendingPathComponent("\(key(word: word, targetLanguage: targetLanguage, senseIndex: senseIndex)).png")
    }
}
