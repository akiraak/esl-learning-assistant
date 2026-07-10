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
    /// 授業日（クラスカレンダー上の日付）の実ストレージ。クラス内で日付は一意。
    /// 既存レッスンは起動時の LessonDateBackfill が createdAt の日付で埋める
    /// （オプショナル追加のためライトウェイトマイグレーションで移行。非オプショナル追加は厳禁）
    var dateStorage: Date?

    /// 授業日の公開 API。未バックフィルの既存行は createdAt の日付として扱う。
    /// 保存値はローカル Calendar の startOfDay に正規化するが、同日判定は保存値の直接比較ではなく
    /// 常に `Calendar.isDate(_:inSameDayAs:)` で行うこと（タイムゾーン変更等のズレに頑健にする）
    var date: Date {
        get { dateStorage ?? Calendar.current.startOfDay(for: createdAt) }
        set { dateStorage = Calendar.current.startOfDay(for: newValue) }
    }

    /// 表示名。タイトルは任意ラベルで、未設定（空・空白のみ）なら授業日を表示する
    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Self.dateTitleFormatter.string(from: date) : trimmed
    }

    private static let dateTitleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("yMdE")
        return formatter
    }()

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

    // 文書（PDF/DOCX）も音声と同型の多対多。レッスンを消してもドキュメント本体は残す（ライブラリ資産として nullify）
    @Relationship(deleteRule: .nullify, inverse: \Document.lessons)
    var documents: [Document] = []

    init(id: UUID = UUID(), schoolClass: Class, title: String, createdAt: Date = .now, memo: String? = nil, date: Date? = nil) {
        self.id = id
        self.schoolClass = schoolClass
        self.title = title
        self.createdAt = createdAt
        self.memo = memo
        self.dateStorage = Calendar.current.startOfDay(for: date ?? createdAt)
    }
}
