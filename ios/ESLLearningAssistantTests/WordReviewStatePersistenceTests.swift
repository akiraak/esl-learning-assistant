import SwiftData
import XCTest
@testable import ESLLearningAssistant

/// WordReviewState が SwiftData ストア経由で正しく永続化されることの回帰テスト。
/// CodingKeys のキー名が実プロパティ名とズレると、エラーにならず値が黙って失われる
/// （docs/plans/archive/review-mastery-persistence-fix.md）。
final class WordReviewStatePersistenceTests: XCTestCase {
    /// アプリ再起動相当（オンディスクストアをコンテナごと開き直し）でも全フィールドが読み戻せる
    func testReviewStateSurvivesStoreRoundTrip() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("review-state-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: storeURL) }

        let wordID = UUID()
        do {
            let context = try makeContext(url: storeURL)
            let word = Word(id: wordID, text: "apple", translation: "りんご")
            context.insert(word)
            try context.save()

            // クイズ解答と同じ流れで更新（正解1回: mastery 20% / correctCount 1）
            word.reviewState = ReviewScheduler.answered(word.reviewState, isCorrect: true)
            try context.save()
        }

        do {
            let context = try makeContext(url: storeURL)
            let word = try XCTUnwrap(
                try context.fetch(FetchDescriptor<Word>()).first { $0.id == wordID }
            )
            XCTAssertEqual(word.reviewState.reviewCount, 1)
            XCTAssertEqual(word.reviewState.correctCount, 1)
            XCTAssertEqual(word.reviewState.masteryPercent, 20)
            XCTAssertEqual(word.reviewState.stepIndex, 0)
            XCTAssertEqual(word.reviewState.lapseCount, 0)
            XCTAssertNotNil(word.reviewState.lastReviewedAt)
        }
    }

    /// 同一コンテナ内の別コンテキストから読んでも更新が見える（保存経路の取りこぼし検知）
    func testReviewStateVisibleFromSecondContext() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Class.self, Lesson.self, Photo.self, Word.self, WordOccurrence.self,
            configurations: config
        )
        let context = ModelContext(container)
        let word = Word(text: "banana", translation: "バナナ")
        context.insert(word)
        word.reviewState = ReviewScheduler.answered(word.reviewState, isCorrect: true)
        try context.save()

        let secondContext = ModelContext(container)
        let fetched = try XCTUnwrap(
            try secondContext.fetch(FetchDescriptor<Word>()).first { $0.text == "banana" }
        )
        XCTAssertEqual(fetched.reviewState.correctCount, 1)
        XCTAssertEqual(fetched.reviewState.masteryPercent, 20)
    }

    private func makeContext(url: URL) throws -> ModelContext {
        let config = ModelConfiguration(url: url)
        let container = try ModelContainer(
            for: Class.self, Lesson.self, Photo.self, Word.self, WordOccurrence.self,
            configurations: config
        )
        return ModelContext(container)
    }
}
