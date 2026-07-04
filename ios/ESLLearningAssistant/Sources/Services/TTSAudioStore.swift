import CryptoKit
import Foundation

/// サーバTTSで生成した音声（WAV）の端末ローカル置き場を管理する。
/// 「生成済み＝再生ボタン」の状態を画面再訪やオフライン時にも維持するため、
/// OSに消されうる Caches ではなく Application Support 配下に保存する。
/// キーはサーバ側（tts_audio.text_hash）と同じ sha256("model|text")。
/// 音声キャラはサーバが生成時にランダム選択するため、キーには含めない。
enum TTSAudioStore {
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("tts", isDirectory: true)
    }

    static func key(text: String, model: String) -> String {
        let digest = SHA256.hash(data: Data("\(model)|\(text)".utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// 保存済みならファイルURLを返す（未生成なら nil）
    static func localURL(text: String, model: String) -> URL? {
        let url = fileURL(text: text, model: model)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// 音声データを保存してファイルURLを返す
    @discardableResult
    static func save(data: Data, text: String, model: String) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = fileURL(text: text, model: model)
        try data.write(to: url, options: .atomic)
        return url
    }

    /// 保存済み音声を全削除する（Settingsのデバッグメニュー等からの利用を想定）
    static func removeAll() {
        try? FileManager.default.removeItem(at: directory)
    }

    private static func fileURL(text: String, model: String) -> URL {
        directory.appendingPathComponent("\(key(text: text, model: model)).wav")
    }
}
