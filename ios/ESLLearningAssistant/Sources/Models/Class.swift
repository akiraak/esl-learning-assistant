import Foundation
import SwiftData

@Model
final class Class {
    var id: UUID
    var name: String
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \Lesson.schoolClass)
    var lessons: [Lesson] = []

    /// 指定日のレッスンを返す（クラス内で授業日は一意）。同日判定はローカル Calendar 基準。
    /// カレンダー UI の出し分けと、作成時の同日重複ガードの両方で使う
    func lesson(on date: Date) -> Lesson? {
        lessons.first { Calendar.current.isDate($0.date, inSameDayAs: date) }
    }

    init(id: UUID = UUID(), name: String, createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
    }
}
