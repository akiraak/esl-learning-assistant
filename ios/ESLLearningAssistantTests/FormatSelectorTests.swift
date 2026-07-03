import XCTest
@testable import ESLLearningAssistant

final class FormatSelectorTests: XCTestCase {
    // MARK: - 形式選定（select）
    // 出題可能な形式の集合はサーバ保存問題の形式一覧から作られる
    // （素材からの出題可否判定はサーバ生成側 backend/src/quizQuestions.ts に移動）

    func testSelectReturnsNilForEmptyAvailability() {
        var generator = SeededGenerator(seed: 1)
        XCTAssertNil(FormatSelector.select(
            availableFormats: [], sessionCounts: [:], using: &generator
        ))
    }

    func testSelectOnlyReturnsAvailableFormats() {
        var generator = SeededGenerator(seed: 1)
        for _ in 0..<20 {
            let selected = FormatSelector.select(
                availableFormats: [.tc9], sessionCounts: [.vc1: 5], using: &generator
            )
            XCTAssertEqual(selected, .tc9)
        }
    }

    func testSessionRatiosConvergeToTargetsWithFullAvailability() {
        // 素材が十分なら実績比率が目標比率（出題 40:50:10、回答 60:30:10）へ収束する
        var generator = SeededGenerator(seed: 42)
        let available = Set(ReviewQuestionFormat.allCases)
        var counts: [ReviewQuestionFormat: Int] = [:]
        let total = 300

        for _ in 0..<total {
            let selected = FormatSelector.select(
                availableFormats: available, sessionCounts: counts, using: &generator
            )
            counts[XCTUnwrap2(selected), default: 0] += 1
        }

        var promptCounts: [ReviewPromptBucket: Int] = [:]
        var answerCounts: [ReviewAnswerBucket: Int] = [:]
        for (format, count) in counts {
            promptCounts[format.promptBucket, default: 0] += count
            answerCounts[format.answerBucket, default: 0] += count
        }
        func ratio(_ count: Int?) -> Double { Double(count ?? 0) / Double(total) }

        XCTAssertEqual(ratio(promptCounts[.text]), 0.4, accuracy: 0.05)
        XCTAssertEqual(ratio(promptCounts[.audio]), 0.5, accuracy: 0.05)
        XCTAssertEqual(ratio(promptCounts[.illustration]), 0.1, accuracy: 0.05)
        XCTAssertEqual(ratio(answerCounts[.choice]), 0.6, accuracy: 0.05)
        XCTAssertEqual(ratio(answerCounts[.typing]), 0.3, accuracy: 0.05)
        XCTAssertEqual(ratio(answerCounts[.illustrationChoice]), 0.1, accuracy: 0.05)
    }

    func testSelectFallsBackWhenTargetBucketsAreUnsatisfiable() {
        // 保存問題が少ない形式構成でも、残りの形式から選び続けて例外を出さない
        var generator = SeededGenerator(seed: 7)
        let available: Set<ReviewQuestionFormat> = [.tc9, .vc2, .vc5]
        var counts: [ReviewQuestionFormat: Int] = [:]

        for _ in 0..<100 {
            guard let selected = FormatSelector.select(
                availableFormats: available, sessionCounts: counts, using: &generator
            ) else {
                return XCTFail("出題可能な形式があるのに nil が返った")
            }
            XCTAssertTrue(available.contains(selected))
            counts[selected, default: 0] += 1
        }
        XCTAssertEqual(counts.values.reduce(0, +), 100)
    }

    // XCTUnwrap は throws のためループ内で使いやすい非throwing版
    private func XCTUnwrap2(_ format: ReviewQuestionFormat?) -> ReviewQuestionFormat {
        guard let format else {
            XCTFail("select が nil を返した")
            return .tc9
        }
        return format
    }
}

/// テストを再現可能にする決定的な乱数生成器（SplitMix64）
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
