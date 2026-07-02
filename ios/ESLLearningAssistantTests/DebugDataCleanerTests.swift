import SwiftData
import XCTest
@testable import ESLLearningAssistant

final class DebugDataCleanerTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Class.self, Lesson.self, Photo.self, Word.self, WordOccurrence.self,
            configurations: config
        )
        return ModelContext(container)
    }

    private func seed(_ context: ModelContext) throws {
        let schoolClass = Class(name: "English")
        let lesson = Lesson(schoolClass: schoolClass, title: "Lesson 1")
        let photo = Photo(lesson: lesson, imageFileName: "test.jpg")
        let word = Word(text: "apple", translation: "りんご")
        let occurrence = WordOccurrence(word: word, lesson: lesson, sourcePhoto: photo)
        context.insert(schoolClass)
        context.insert(lesson)
        context.insert(photo)
        context.insert(word)
        context.insert(occurrence)
        try context.save()
    }

    private func count<T: PersistentModel>(_ type: T.Type, in context: ModelContext) throws -> Int {
        try context.fetchCount(FetchDescriptor<T>())
    }

    func testDeleteAllDataRemovesEverything() throws {
        let context = try makeContext()
        try seed(context)

        try DebugDataCleaner.deleteAllData(context: context)

        XCTAssertEqual(try count(Class.self, in: context), 0)
        XCTAssertEqual(try count(Lesson.self, in: context), 0)
        XCTAssertEqual(try count(Photo.self, in: context), 0)
        XCTAssertEqual(try count(Word.self, in: context), 0)
        XCTAssertEqual(try count(WordOccurrence.self, in: context), 0)
    }

    func testDeleteAllClassesKeepsWords() throws {
        let context = try makeContext()
        try seed(context)

        try DebugDataCleaner.deleteAllClasses(context: context)

        XCTAssertEqual(try count(Class.self, in: context), 0)
        XCTAssertEqual(try count(Lesson.self, in: context), 0)
        XCTAssertEqual(try count(Photo.self, in: context), 0)
        XCTAssertEqual(try count(WordOccurrence.self, in: context), 0)
        XCTAssertEqual(try count(Word.self, in: context), 1)
    }

    func testDeleteClassRemovesOnlyThatClass() throws {
        let context = try makeContext()
        let classA = Class(name: "Class A")
        let lessonA = Lesson(schoolClass: classA, title: "A-1")
        let photoA = Photo(lesson: lessonA, imageFileName: "a.jpg")
        let classB = Class(name: "Class B")
        let lessonB = Lesson(schoolClass: classB, title: "B-1")
        let photoB = Photo(lesson: lessonB, imageFileName: "b.jpg")
        let word = Word(text: "apple", translation: "りんご")
        let occurrenceA = WordOccurrence(word: word, lesson: lessonA, sourcePhoto: photoA)
        let occurrenceB = WordOccurrence(word: word, lesson: lessonB, sourcePhoto: photoB)
        for model in [classA, lessonA, photoA, classB, lessonB, photoB] as [any PersistentModel] {
            context.insert(model)
        }
        context.insert(word)
        context.insert(occurrenceA)
        context.insert(occurrenceB)
        try context.save()

        try DebugDataCleaner.deleteClass(classA, context: context)

        XCTAssertEqual(try count(Class.self, in: context), 1)
        XCTAssertEqual(try count(Lesson.self, in: context), 1)
        XCTAssertEqual(try count(Photo.self, in: context), 1)
        XCTAssertEqual(try count(WordOccurrence.self, in: context), 1)
        XCTAssertEqual(try count(Word.self, in: context), 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Class>()).first?.name, "Class B")
        XCTAssertEqual(try context.fetch(FetchDescriptor<Lesson>()).first?.title, "B-1")
    }

    func testDeleteAllWordsKeepsClassesAndPhotos() throws {
        let context = try makeContext()
        try seed(context)

        try DebugDataCleaner.deleteAllWords(context: context)

        XCTAssertEqual(try count(Word.self, in: context), 0)
        XCTAssertEqual(try count(WordOccurrence.self, in: context), 0)
        XCTAssertEqual(try count(Class.self, in: context), 1)
        XCTAssertEqual(try count(Lesson.self, in: context), 1)
        XCTAssertEqual(try count(Photo.self, in: context), 1)
    }
}
