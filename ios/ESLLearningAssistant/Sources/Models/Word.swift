import Foundation
import SwiftData

@Model
final class Word {
    var id: UUID
    var text: String
    var translation: String
    var exampleSentence: String?
    var exampleSentenceSource: ExampleSentenceSource?
    var partOfSpeech: String?
    var grammarNote: String?
    var registeredAt: Date
    var reviewState: WordReviewState

    @Relationship(deleteRule: .cascade, inverse: \WordOccurrence.word)
    var occurrences: [WordOccurrence] = []

    init(
        id: UUID = UUID(),
        text: String,
        translation: String,
        exampleSentence: String? = nil,
        exampleSentenceSource: ExampleSentenceSource? = nil,
        partOfSpeech: String? = nil,
        grammarNote: String? = nil,
        registeredAt: Date = .now
    ) {
        self.id = id
        self.text = text
        self.translation = translation
        self.exampleSentence = exampleSentence
        self.exampleSentenceSource = exampleSentenceSource
        self.partOfSpeech = partOfSpeech
        self.grammarNote = grammarNote
        self.registeredAt = registeredAt
        self.reviewState = WordReviewState(dueDate: registeredAt)
    }
}

enum ExampleSentenceSource: String, Codable {
    case textbook
    case aiGenerated
}

struct WordReviewState: Codable {
    var dueDate: Date
    var lastReviewedAt: Date?
    var reviewCount: Int

    init(dueDate: Date, lastReviewedAt: Date? = nil, reviewCount: Int = 0) {
        self.dueDate = dueDate
        self.lastReviewedAt = lastReviewedAt
        self.reviewCount = reviewCount
    }
}
