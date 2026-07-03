import XCTest
@testable import ESLLearningAssistant

final class FormatSelectorTests: XCTestCase {
    // MARK: - フィクスチャ

    private func makeAIInfo(
        senses: [WordAIInfo.Sense] = [
            .init(meaning: "走る", englishDefinition: "to move quickly on foot", partOfSpeech: "動詞", note: nil)
        ],
        inflections: [WordAIInfo.Inflection] = [.init(form: "過去形", text: "ran")],
        examples: [WordAIInfo.Example] = [.init(english: "I run every day.", translation: "毎日走る。")],
        collocations: [String] = ["run fast"],
        synonyms: [String] = ["sprint"],
        antonyms: [String] = ["stop"]
    ) -> WordAIInfo {
        WordAIInfo(
            senses: senses,
            pronunciation: .init(ipa: "/rʌn/", syllables: nil),
            inflections: inflections,
            examples: examples,
            collocations: collocations,
            synonyms: synonyms,
            antonyms: antonyms,
            usageNote: nil,
            cefrLevel: "A1",
            etymology: nil,
            register: nil,
            commonMistakes: nil
        )
    }

    private let fullPool = ReviewDistractorPool(
        wordCount: 10, definitionCount: 10, exampleCount: 10, illustrationCount: 10
    )

    // MARK: - 出題可否（availableFormats）

    func testFullMaterialMakesAllFormatsAvailable() {
        let material = ReviewWordMaterial(
            text: "run", aiInfo: makeAIInfo(), hasIllustration: true, distractors: fullPool
        )
        XCTAssertEqual(
            FormatSelector.availableFormats(for: material),
            Set(ReviewQuestionFormat.allCases)
        )
    }

    func testWordWithoutAIInfoFallsBackToTextOnlyFormats() {
        // aiInfo 未生成の単語は text だけで組める形式のみ（プラン §3.3）
        let material = ReviewWordMaterial(
            text: "run", aiInfo: nil, hasIllustration: false, distractors: fullPool
        )
        XCTAssertEqual(
            FormatSelector.availableFormats(for: material),
            [.tc9, .vc2, .vc5, .vt1]
        )
    }

    func testEmptyDistractorPoolLeavesSelfContainedFormats() {
        // 登録語が自分だけでも、機械生成の誤答で組める形式は残る
        let material = ReviewWordMaterial(
            text: "run", aiInfo: nil, hasIllustration: false, distractors: .empty
        )
        XCTAssertEqual(
            FormatSelector.availableFormats(for: material),
            [.tc9, .vc2, .vt1]
        )
    }

    func testMultiSenseWordExcludesTC10() {
        // TC10（文中語義）は senses が1件の単語に限定
        let multiSense = makeAIInfo(senses: [
            .init(meaning: "経営する", englishDefinition: "to manage a business", partOfSpeech: "動詞", note: nil),
            .init(meaning: "走る", englishDefinition: "to move quickly on foot", partOfSpeech: "動詞", note: nil),
        ])
        let material = ReviewWordMaterial(
            text: "run", aiInfo: multiSense, hasIllustration: true, distractors: fullPool
        )
        let available = FormatSelector.availableFormats(for: material)
        XCTAssertFalse(available.contains(.tc10))
        XCTAssertTrue(available.contains(.tc1))
    }

    func testUnknownGrammarLabelsExcludeMappedFormats() {
        // マッピングに無い品詞・活用形ラベルの単語では TC7・TC8・TT3・VC7 を出題しない
        let unknownLabels = makeAIInfo(
            senses: [.init(meaning: "?", englishDefinition: "some definition", partOfSpeech: "分詞", note: nil)],
            inflections: [.init(form: "未知の形", text: "???")]
        )
        let material = ReviewWordMaterial(
            text: "run", aiInfo: unknownLabels, hasIllustration: true, distractors: fullPool
        )
        let available = FormatSelector.availableFormats(for: material)
        XCTAssertFalse(available.contains(.tc7))
        XCTAssertFalse(available.contains(.tc8))
        XCTAssertFalse(available.contains(.tt3))
        XCTAssertFalse(available.contains(.vc7))
        XCTAssertTrue(available.contains(.tc1))
    }

    func testPartOfSpeechOutsideChoiceSetExcludesTC8() {
        // マッピング可能でも固定4択（noun/verb/adjective/adverb）に無い品詞は TC8 対象外
        let preposition = makeAIInfo(
            senses: [.init(meaning: "〜の中に", englishDefinition: "expressing location", partOfSpeech: "前置詞", note: nil)]
        )
        let material = ReviewWordMaterial(
            text: "in", aiInfo: preposition, hasIllustration: false, distractors: fullPool
        )
        XCTAssertFalse(FormatSelector.availableFormats(for: material).contains(.tc8))
    }

    func testIllustrationFormatsRequireIllustrations() {
        // 自分のイラストが無い → イラストを使う4形式すべて対象外
        let noOwnIllustration = ReviewWordMaterial(
            text: "run", aiInfo: makeAIInfo(), hasIllustration: false, distractors: fullPool
        )
        let available1 = FormatSelector.availableFormats(for: noOwnIllustration)
        for format in [ReviewQuestionFormat.tc11, .ic1, .it1, .vc8] {
            XCTAssertFalse(available1.contains(format), "\(format)")
        }

        // 自分のイラストはあるが他単語のイラストが3枚未満 → イラスト4択のみ対象外
        var fewIllustrations = fullPool
        fewIllustrations.illustrationCount = 2
        let noPool = ReviewWordMaterial(
            text: "run", aiInfo: makeAIInfo(), hasIllustration: true, distractors: fewIllustrations
        )
        let available2 = FormatSelector.availableFormats(for: noPool)
        XCTAssertFalse(available2.contains(.tc11))
        XCTAssertFalse(available2.contains(.vc8))
        XCTAssertTrue(available2.contains(.ic1))
        XCTAssertTrue(available2.contains(.it1))
    }

    // MARK: - 形式選定（select）

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
        // 素材不足でイラスト・タイプ入力系が組めなくても、残りの形式から選び続けて例外を出さない
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
