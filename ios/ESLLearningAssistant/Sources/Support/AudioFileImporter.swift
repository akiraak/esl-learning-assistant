import Foundation
import SwiftData

/// iOS の「ファイル」ピッカー（.fileImporter / UIDocumentPicker）で選ばれた音声URLを
/// アプリに取り込み、AudioClip 化する共通処理。Dropbox・iCloud・端末内など Files に見える
/// 場所すべてから取り込める。
enum AudioFileImporter {
    /// バックグラウンドで読み込み（＋正規化）を終えた1ファイルぶんの保存待ちデータ。
    private struct LoadedAudio: Sendable {
        let data: Data
        let ext: String
    }

    /// 選択されたファイルURL群を取り込み、作成したクリップ数を返す。
    /// `normalize` が true なら音量ノーマライズ（AudioNormalizer）を掛けて `.aac` で保存する。
    /// 正規化（デコード＋エンコード）は長尺ファイルで数秒かかり得るため、
    /// ファイル読み込みごとバックグラウンドで実行し、モデル操作だけメインで行う。
    @MainActor
    @discardableResult
    static func importFiles(
        _ urls: [URL],
        into lesson: Lesson?,
        context: ModelContext,
        normalize: Bool
    ) async -> Int {
        var count = 0
        for url in urls {
            let loaded = await Task.detached(priority: .userInitiated) {
                loadAudio(url: url, normalize: normalize)
            }.value
            guard let loaded else { continue }
            guard let fileName = AudioStorage.save(data: loaded.data, ext: loaded.ext) else { continue }

            let title = url.deletingPathExtension().lastPathComponent
            let clip = AudioClip(
                title: title.isEmpty ? url.lastPathComponent : title,
                audioFileName: fileName,
                sourcePath: nil,
                byteSize: loaded.data.count,
                lessons: lesson.map { [$0] } ?? []
            )
            context.insert(clip)
            count += 1
        }
        if count > 0 {
            context.saveOrLog()
        }
        return count
    }

    /// セキュリティスコープ付きURLからデータを読み、必要なら音量ノーマライズを掛ける。
    /// ドキュメントピッカーのURLはセキュリティスコープ付きなので明示的にアクセス開始/終了する。
    /// 正規化に失敗した場合（無音スキップ含む）は元データにフォールバックする（従来動作の維持）。
    private static func loadAudio(url: URL, normalize: Bool) -> LoadedAudio? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url) else { return nil }
        let ext = url.pathExtension
        guard normalize else { return LoadedAudio(data: data, ext: ext) }

        // AudioNormalizer はファイルURL入力なので、スコープに依存しない一時コピーを経由する
        let cleanExt = ext.lowercased()
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "audio-import-\(UUID().uuidString)" + (cleanExt.isEmpty ? "" : ".\(cleanExt)")
            )
        defer { try? FileManager.default.removeItem(at: tempURL) }
        do {
            try data.write(to: tempURL)
            guard let normalizedURL = try AudioNormalizer.normalize(inputURL: tempURL) else {
                return LoadedAudio(data: data, ext: ext) // 実質無音 → 正規化スキップ
            }
            defer { try? FileManager.default.removeItem(at: normalizedURL) }
            return LoadedAudio(data: try Data(contentsOf: normalizedURL), ext: "aac")
        } catch {
            return LoadedAudio(data: data, ext: ext) // デコード・エンコード不能 → 元データを保存
        }
    }
}
