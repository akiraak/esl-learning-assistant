import Foundation
import SwiftData

/// iOSの「ファイル」（Dropbox・iCloud・端末内）から取り込んでアプリの正式データにした音声クリップ。
/// 実体（音声バイナリ）は AudioStorage（Documents/Audio）にファイルで置き、ここはメタデータのみ持つ。
/// レッスンへの紐付けは任意かつ複数可（単語と同様、複数レッスンへ付けられるしレッスン非依存の
/// ライブラリ音声も許容する）。inverse は `Lesson.audioClips` 側で定義する。
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
    /// 紐付くレッスン（0個以上）。レッスン削除時は nullify されクリップ自体は残る。
    var lessons: [Lesson] = []

    init(
        id: UUID = UUID(),
        title: String,
        audioFileName: String,
        sourcePath: String? = nil,
        byteSize: Int = 0,
        importedAt: Date = .now,
        lessons: [Lesson] = []
    ) {
        self.id = id
        self.title = title
        self.audioFileName = audioFileName
        self.sourcePath = sourcePath
        self.byteSize = byteSize
        self.importedAt = importedAt
        self.lessons = lessons
    }
}
