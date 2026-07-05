import Foundation
import SwiftData

/// iOS の「ファイル」ピッカー（.fileImporter / UIDocumentPicker）で選ばれた音声URLを
/// アプリに取り込み、AudioClip 化する共通処理。Dropbox・iCloud・端末内など Files に見える
/// 場所すべてから取り込める。
enum AudioFileImporter {
    /// 選択されたファイルURL群を取り込み、作成したクリップ数を返す。
    /// ドキュメントピッカーのURLはセキュリティスコープ付きなので明示的にアクセス開始/終了する。
    @discardableResult
    static func importFiles(_ urls: [URL], into lesson: Lesson?, context: ModelContext) -> Int {
        var count = 0
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }

            guard let data = try? Data(contentsOf: url) else { continue }
            let ext = url.pathExtension
            guard let fileName = AudioStorage.save(data: data, ext: ext) else { continue }

            let title = url.deletingPathExtension().lastPathComponent
            let clip = AudioClip(
                title: title.isEmpty ? url.lastPathComponent : title,
                audioFileName: fileName,
                sourcePath: nil,
                byteSize: data.count,
                lesson: lesson
            )
            context.insert(clip)
            count += 1
        }
        if count > 0 {
            context.saveOrLog()
        }
        return count
    }
}
