import XCTest
@testable import ESLLearningAssistant

/// stepIndex / correctCount / lapseCount 追加前に保存されたデータの後方互換を確認する。
final class WordReviewStateTests: XCTestCase {
    func testDecodeLegacyDataWithoutNewFields() throws {
        // 旧フィールドのみのJSON（Dateは既定のtimeIntervalSinceReferenceDate表現）
        let legacyJSON = """
        {"dueDate": 773000000, "lastReviewedAt": 772900000, "reviewCount": 2}
        """
        let data = try XCTUnwrap(legacyJSON.data(using: .utf8))
        let state = try JSONDecoder().decode(WordReviewState.self, from: data)

        XCTAssertEqual(state.dueDate, Date(timeIntervalSinceReferenceDate: 773_000_000))
        XCTAssertEqual(state.reviewCount, 2)
        XCTAssertEqual(state.stepIndex, 0)
        XCTAssertEqual(state.correctCount, 0)
        XCTAssertEqual(state.lapseCount, 0)
    }

    func testEncodeDecodeRoundTripKeepsNewFields() throws {
        let state = WordReviewState(
            dueDate: Date(timeIntervalSinceReferenceDate: 773_000_000),
            lastReviewedAt: Date(timeIntervalSinceReferenceDate: 772_900_000),
            reviewCount: 5,
            stepIndex: 3,
            correctCount: 4,
            lapseCount: 1
        )
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(WordReviewState.self, from: data)

        XCTAssertEqual(decoded.dueDate, state.dueDate)
        XCTAssertEqual(decoded.lastReviewedAt, state.lastReviewedAt)
        XCTAssertEqual(decoded.reviewCount, 5)
        XCTAssertEqual(decoded.stepIndex, 3)
        XCTAssertEqual(decoded.correctCount, 4)
        XCTAssertEqual(decoded.lapseCount, 1)
    }
}
