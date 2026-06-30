import Foundation
import SwiftData

@Model
final class Lesson {
    var id: UUID
    var schoolClass: Class
    var title: String
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \Photo.lesson)
    var photos: [Photo] = []

    init(id: UUID = UUID(), schoolClass: Class, title: String, createdAt: Date = .now) {
        self.id = id
        self.schoolClass = schoolClass
        self.title = title
        self.createdAt = createdAt
    }
}
