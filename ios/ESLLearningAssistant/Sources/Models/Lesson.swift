import Foundation
import SwiftData

@Model
final class Lesson {
    var id: UUID
    var schoolClass: Class
    var title: String
    var createdAt: Date
    /// レッスンへの自由記述メモ。未入力は nil（オプショナル追加のためライトウェイトマイグレーションで移行）
    var memo: String?

    @Relationship(deleteRule: .cascade, inverse: \Photo.lesson)
    var photos: [Photo] = []

    // YouTube リンクはレッスン固有コンテンツ。写真と同じく to-one/cascade（レッスン削除で一緒に消す）
    @Relationship(deleteRule: .cascade, inverse: \YouTubeLink.lesson)
    var youtubeLinks: [YouTubeLink] = []

    @Relationship(deleteRule: .cascade, inverse: \WordOccurrence.lesson)
    var wordOccurrences: [WordOccurrence] = []

    // 音声は多対多。レッスンを消してもクリップ本体は残す（ライブラリ資産として nullify）
    @Relationship(deleteRule: .nullify, inverse: \AudioClip.lessons)
    var audioClips: [AudioClip] = []

    init(id: UUID = UUID(), schoolClass: Class, title: String, createdAt: Date = .now, memo: String? = nil) {
        self.id = id
        self.schoolClass = schoolClass
        self.title = title
        self.createdAt = createdAt
        self.memo = memo
    }
}
