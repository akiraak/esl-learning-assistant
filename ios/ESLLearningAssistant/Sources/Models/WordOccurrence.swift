import Foundation
import SwiftData

@Model
final class WordOccurrence {
    var id: UUID
    var word: Word
    var lesson: Lesson
    var sourcePhoto: Photo?
    var occurredAt: Date

    init(
        id: UUID = UUID(),
        word: Word,
        lesson: Lesson,
        sourcePhoto: Photo? = nil,
        occurredAt: Date = .now
    ) {
        self.id = id
        self.word = word
        self.lesson = lesson
        self.sourcePhoto = sourcePhoto
        self.occurredAt = occurredAt
    }
}
