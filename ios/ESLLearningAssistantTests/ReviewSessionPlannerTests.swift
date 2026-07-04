import XCTest
@testable import ESLLearningAssistant

final class ReviewSessionPlannerTests: XCTestCase {
    // MARK: - plan（事前確定）

    func testPlanPicksOneQuestionPerWordInOrder() {
        var generator = SeededGenerator(seed: 1)
        let questions: [Int: [ReviewQuestion]] = [
            1: [question(.tc1), question(.vc1, audioText: "one")],
            2: [question(.tc2)],
            3: [question(.tt1), question(.vt1, audioText: "three")],
        ]
        let plan = ReviewSessionPlanner.plan(
            wordIDs: [1, 2, 3], questionsByWordID: questions, using: &generator
        )

        XCTAssertEqual(plan.questions.map(\.wordID), [1, 2, 3])
        XCTAssertEqual(plan.sessionCounts.values.reduce(0, +), 3)
        for (wordID, question) in plan.questions {
            XCTAssertTrue(questions[wordID]!.contains { $0.format == question.format })
        }
    }

    func testPlanSkipsWordsWithoutQuestions() {
        var generator = SeededGenerator(seed: 2)
        let plan = ReviewSessionPlanner.plan(
            wordIDs: [1, 2], questionsByWordID: [2: [question(.tc1)]], using: &generator
        )
        XCTAssertEqual(plan.questions.map(\.wordID), [2])
    }

    func testPlanMatchesSequentialFormatSelectorBehavior() {
        // 事前確定は「出題直前に逐次選択」と同じ挙動になること（同一シードで再現）
        let questions = Dictionary(uniqueKeysWithValues: (0..<20).map { id in
            (id, ReviewQuestionFormat.allCases.map { question($0, audioText: $0.rawValue.hasPrefix("v") ? "audio" : nil) })
        })

        var planGenerator = SeededGenerator(seed: 42)
        let plan = ReviewSessionPlanner.plan(
            wordIDs: Array(0..<20), questionsByWordID: questions, using: &planGenerator
        )

        var sequentialGenerator = SeededGenerator(seed: 42)
        var counts: [ReviewQuestionFormat: Int] = [:]
        var sequential: [ReviewQuestionFormat] = []
        for id in 0..<20 {
            let picked = ReviewSessionPlanner.pick(
                from: questions[id]!, sessionCounts: counts, using: &sequentialGenerator
            )!
            counts[picked.format, default: 0] += 1
            sequential.append(picked.format)
        }

        XCTAssertEqual(plan.questions.map(\.question.format), sequential)
        XCTAssertEqual(plan.sessionCounts, counts)
    }

    // MARK: - replacingFailedAudio（DL失敗時の差し替え）

    func testReplacingFailedAudioSwapsToPlayableQuestion() {
        var generator = SeededGenerator(seed: 3)
        let questions: [Int: [ReviewQuestion]] = [
            1: [question(.vc1, audioText: "failed text"), question(.tc1), question(.tt1)],
        ]
        let plan = ReviewSessionPlanner.Plan(
            questions: [(wordID: 1, question: question(.vc1, audioText: "failed text"))],
            sessionCounts: [.vc1: 1]
        )

        let replaced = ReviewSessionPlanner.replacingFailedAudio(
            plan: plan,
            questionsByWordID: questions,
            failedTexts: ["failed text"],
            hasLocalAudio: { _ in false },
            using: &generator
        )

        XCTAssertEqual(replaced.questions.count, 1)
        let format = replaced.questions[0].question.format
        XCTAssertNil(replaced.questions[0].question.audioText)
        XCTAssertTrue([.tc1, .tt1].contains(format))
        // カウントも差し替え後の形式に付け替わる
        XCTAssertEqual(replaced.sessionCounts[.vc1], 0)
        XCTAssertEqual(replaced.sessionCounts[format], 1)
    }

    func testReplacingFailedAudioAllowsAudioQuestionWithLocalFile() {
        // 差し替え先が音声形式でも、ローカルに音声があれば選べる
        var generator = SeededGenerator(seed: 4)
        let questions: [Int: [ReviewQuestion]] = [
            1: [question(.vc1, audioText: "failed text"), question(.vc2, audioText: "cached text")],
        ]
        let plan = ReviewSessionPlanner.Plan(
            questions: [(wordID: 1, question: question(.vc1, audioText: "failed text"))],
            sessionCounts: [.vc1: 1]
        )

        let replaced = ReviewSessionPlanner.replacingFailedAudio(
            plan: plan,
            questionsByWordID: questions,
            failedTexts: ["failed text"],
            hasLocalAudio: { $0 == "cached text" },
            using: &generator
        )

        XCTAssertEqual(replaced.questions.map(\.question.format), [.vc2])
    }

    func testReplacingFailedAudioDropsWordWithoutCandidates() {
        var generator = SeededGenerator(seed: 5)
        let questions: [Int: [ReviewQuestion]] = [
            1: [question(.vc1, audioText: "failed text")],
            2: [question(.tc1)],
        ]
        let plan = ReviewSessionPlanner.Plan(
            questions: [
                (wordID: 1, question: question(.vc1, audioText: "failed text")),
                (wordID: 2, question: question(.tc1)),
            ],
            sessionCounts: [.vc1: 1, .tc1: 1]
        )

        let replaced = ReviewSessionPlanner.replacingFailedAudio(
            plan: plan,
            questionsByWordID: questions,
            failedTexts: ["failed text"],
            hasLocalAudio: { _ in false },
            using: &generator
        )

        XCTAssertEqual(replaced.questions.map(\.wordID), [2])
        XCTAssertEqual(replaced.sessionCounts[.vc1], 0)
    }

    func testReplacingFailedAudioKeepsUnaffectedQuestions() {
        var generator = SeededGenerator(seed: 6)
        let questions: [Int: [ReviewQuestion]] = [
            1: [question(.vc1, audioText: "ok text")],
            2: [question(.tc1)],
        ]
        let plan = ReviewSessionPlanner.Plan(
            questions: [
                (wordID: 1, question: question(.vc1, audioText: "ok text")),
                (wordID: 2, question: question(.tc1)),
            ],
            sessionCounts: [.vc1: 1, .tc1: 1]
        )

        let replaced = ReviewSessionPlanner.replacingFailedAudio(
            plan: plan,
            questionsByWordID: questions,
            failedTexts: ["other text"],
            hasLocalAudio: { _ in false },
            using: &generator
        )

        XCTAssertEqual(replaced.questions.map(\.question.format), [.vc1, .tc1])
        XCTAssertEqual(replaced.sessionCounts, plan.sessionCounts)
    }

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
