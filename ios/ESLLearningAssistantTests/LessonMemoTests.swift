import SwiftData
import XCTest
@testable import ESLLearningAssistant

final class LessonMemoTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Class.self, Lesson.self, Photo.self, Word.self, WordOccurrence.self,
            configurations: config
        )
        return ModelContext(container)
    }

    private func makeLesson(in context: ModelContext, memo: String? = nil) throws -> Lesson {
        let schoolClass = Class(name: "ESL Beginner A")
        let lesson = Lesson(schoolClass: schoolClass, title: "Unit 1", memo: memo)
        context.insert(schoolClass)
        context.insert(lesson)
        try context.save()
        return lesson
    }

    func testMemoIsNilByDefault() throws {
        let context = try makeContext()
        let lesson = try makeLesson(in: context)

        XCTAssertNil(lesson.memo)
    }

    func testMemoCanBeSavedAndUpdated() throws {
        let context = try makeContext()
        let lesson = try makeLesson(in: context)

        lesson.memo = "Homework: page 12"
        try context.save()

        let lessonID = lesson.id
        let fetched = try context.fetch(
            FetchDescriptor<Lesson>(predicate: #Predicate { $0.id == lessonID })
        )
        XCTAssertEqual(fetched.first?.memo, "Homework: page 12")

        lesson.memo = "Review vocabulary"
        try context.save()
        XCTAssertEqual(fetched.first?.memo, "Review vocabulary")
    }

    func testMemoCanBeCleared() throws {
        let context = try makeContext()
        let lesson = try makeLesson(in: context, memo: "temp note")
        XCTAssertEqual(lesson.memo, "temp note")

        lesson.memo = nil
        try context.save()

        XCTAssertNil(lesson.memo)
    }
}
