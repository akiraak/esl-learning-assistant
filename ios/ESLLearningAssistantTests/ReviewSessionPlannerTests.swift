import XCTest
@testable import ESLLearningAssistant

final class ReviewSessionPlannerTests: XCTestCase {
    // MARK: - pick

    func testPickLimitsVariantsToSelectedFormat() {
        var generator = SeededGenerator(seed: 7)
        let candidates = [
            question(.tc1, instruction: "a"),
            question(.tc1, instruction: "b"),
        ]
        for _ in 0..<10 {
            let picked = ReviewSessionPlanner.pick(
                from: candidates, sessionCounts: [:], using: &generator
            )
            XCTAssertEqual(picked?.format, .tc1)
        }
    }

    func testPickRespectsSessionCountsForRatioAdjustment() {
        // 比率調整: テキスト系ばかり出題済みなら不足している音声系の形式が選ばれる
        var generator = SeededGenerator(seed: 9)
        let candidates = [question(.tc1), question(.vc1, audioText: "audio")]
        let picked = ReviewSessionPlanner.pick(
            from: candidates, sessionCounts: [.tc1: 5], using: &generator
        )
        XCTAssertEqual(picked?.format, .vc1)
    }

    func testPickReturnsNilForEmptyCandidates() {
        var generator = SeededGenerator(seed: 8)
        XCTAssertNil(ReviewSessionPlanner.pick(from: [], sessionCounts: [:], using: &generator))
    }

    // MARK: - ヘルパー

    private func question(
        _ format: ReviewQuestionFormat,
        audioText: String? = nil,
        instruction: String = "instruction"
    ) -> ReviewQuestion {
        ReviewQuestion(
            format: format,
            instruction: instruction,
            displayText: nil,
            audioText: audioText,
            promptIllustrationWord: nil,
            answer: .choices(options: ["a", "b", "c", "d"], correctIndex: 0)
        )
    }
}

/// テストを再現可能にする決定的な乱数生成器（SplitMix64。FormatSelectorTests と同じ実装）
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
