import Foundation
import SwiftData

/// iOSの「ファイル」（Dropbox・iCloud・端末内）から取り込んでアプリの正式データにした音声クリップ。
/// 実体（音声バイナリ）は AudioStorage（Documents/Audio）にファイルで置き、ここはメタデータのみ持つ。
/// レッスンへの紐付けは任意（単語と同様、レッスン非依存のライブラリ音声も許容する）。
@Model
final class AudioClip {
    var id: UUID
    /// 表示名。既定は取り込んだファイル名から拡張子を除いたもの。ユーザーが編集可能。
    var title: String
    /// AudioStorage 内の実ファイル名（`UUID.ext`）
    var audioFileName: String
    /// 取り込み元の参照用パス（将来利用のための予備。ファイル取り込みでは付かず nil）。
    var sourcePath: String?
    var byteSize: Int
    var importedAt: Date
    /// 紐付くレッスン（任意）
    var lesson: Lesson?

    init(
        id: UUID = UUID(),
        title: String,
        audioFileName: String,
        sourcePath: String? = nil,
        byteSize: Int = 0,
        importedAt: Date = .now,
        lesson: Lesson? = nil
    ) {
        self.id = id
        self.title = title
        self.audioFileName = audioFileName
        self.sourcePath = sourcePath
        self.byteSize = byteSize
        self.importedAt = importedAt
        self.lesson = lesson
    }
}
