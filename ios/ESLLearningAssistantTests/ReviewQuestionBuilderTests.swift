import XCTest
@testable import ESLLearningAssistant

final class ReviewQuestionBuilderTests: XCTestCase {
    // MARK: - フィクスチャ

    private func makeAIInfo(
        senses: [WordAIInfo.Sense] = [
            .init(meaning: "走る", englishDefinition: "to move quickly on foot", partOfSpeech: "動詞", note: nil)
        ],
        inflections: [WordAIInfo.Inflection] = [.init(form: "過去形", text: "ran")],
        examples: [WordAIInfo.Example] = [.init(english: "I run every day.", translation: "毎日走る。")],
        collocations: [String] = ["run fast"],
        synonyms: [String] = ["sprint"],
        antonyms: [String] = ["stop"],
        cefrLevel: String? = "A1"
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
            cefrLevel: cefrLevel,
            etymology: nil,
            register: nil,
            commonMistakes: nil
        )
    }

    /// 誤答素材（10単語分。定義・例文・イラストすべて持つ）
    private var fullDistractors: [ReviewDistractorMaterial] {
        (1...10).map { index in
            ReviewDistractorMaterial(
                text: "word\(index)",
                englishDefinition: "definition of word\(index)",
                example: "This is example sentence \(index).",
                hasIllustration: true,
                partOfSpeechEnglish: index % 2 == 0 ? "verb" : "noun",
                cefrLevel: index % 2 == 0 ? "A1" : "B2"
            )
        }
    }

    private func makeMaterial(
        text: String = "run",
        aiInfo: WordAIInfo? = nil,
        hasIllustration: Bool = true
    ) -> ReviewWordMaterial {
        ReviewWordMaterial(
            text: text,
            aiInfo: aiInfo ?? makeAIInfo(),
            hasIllustration: hasIllustration,
            distractors: ReviewDistractorPool(materials: fullDistractors)
        )
    }

    private func build(
        _ format: ReviewQuestionFormat,
        material: ReviewWordMaterial? = nil,
        distractors: [ReviewDistractorMaterial]? = nil,
        seed: UInt64 = 1
    ) -> ReviewQuestion? {
        var generator = SeededGenerator(seed: seed)
        return ReviewQuestionBuilder.build(
            format: format,
            material: material ?? makeMaterial(),
            distractors: distractors ?? fullDistractors,
            using: &generator
        )
    }

    private func choices(of question: ReviewQuestion?) -> (options: [String], correctIndex: Int)? {
        switch question?.answer {
        case .choices(let options, let correctIndex),
             .illustrationChoices(let options, let correctIndex):
            return (options, correctIndex)
        default:
            return nil
        }
    }

    // MARK: - 4択の基本性質（全形式）

    func testChoiceFormatsProduceFourUniqueOptionsWithCorrectAnswer() throws {
        // 4択系の全形式で: 4択・重複なし・correctIndex が正答を指す
        let choiceFormats = ReviewQuestionFormat.allCases.filter { $0.answerBucket != .typing }
        for format in choiceFormats {
            for seed: UInt64 in [1, 2, 42] {
                let question = build(format, seed: seed)
                let answer = try XCTUnwrap(choices(of: question), "\(format) が組めなかった")
                XCTAssertEqual(answer.options.count, 4, "\(format)")
                let keys = answer.options.map { ReviewAnswerJudge.normalize($0) }
                XCTAssertEqual(Set(keys).count, 4, "\(format) の選択肢が重複: \(answer.options)")
                XCTAssertTrue(answer.options.indices.contains(answer.correctIndex), "\(format)")
            }
        }
    }

    func testTC1CorrectAnswerIsTargetWord() throws {
        let question = try XCTUnwrap(build(.tc1))
        let answer = try XCTUnwrap(choices(of: question))
        XCTAssertEqual(answer.options[answer.correctIndex], "run")
        XCTAssertEqual(question.displayText, "to move quickly on foot")
    }

    func testTC2CorrectAnswerIsDefinitionAndDistractorsAreOtherDefinitions() throws {
        let question = try XCTUnwrap(build(.tc2))
        let answer = try XCTUnwrap(choices(of: question))
        XCTAssertEqual(answer.options[answer.correctIndex], "to move quickly on foot")
        for (index, option) in answer.options.enumerated() where index != answer.correctIndex {
            XCTAssertTrue(option.hasPrefix("definition of"), "誤答は他単語の定義から: \(option)")
        }
    }

    // MARK: - 例文の空所化

    func testTC3BlanksTargetWordInExample() throws {
        let question = try XCTUnwrap(build(.tc3))
        let display = try XCTUnwrap(question.displayText)
        XCTAssertTrue(display.contains("_____"))
        XCTAssertFalse(display.lowercased().contains("run"))
        let answer = try XCTUnwrap(choices(of: question))
        XCTAssertEqual(answer.options[answer.correctIndex], "run")
    }

    func testBlankingMatchesInflectedForm() throws {
        // 例文に本体が現れず活用形（ran）だけの場合、活用形を空所化し正答も活用形になる
        let info = makeAIInfo(examples: [.init(english: "She ran to school.", translation: "")])
        let question = try XCTUnwrap(build(.tc3, material: makeMaterial(aiInfo: info)))
        XCTAssertEqual(question.displayText, "She _____ to school.")
        let answer = try XCTUnwrap(choices(of: question))
        XCTAssertEqual(answer.options[answer.correctIndex], "ran")
    }

    func testBlankingRequiresWordBoundary() {
        // "running" の中の "run" のような部分一致では空所化しない（\b 境界判定）
        let info = makeAIInfo(
            inflections: [],
            examples: [.init(english: "The runner keeps running.", translation: "")]
        )
        XCTAssertNil(build(.tc3, material: makeMaterial(aiInfo: info)))
    }

    func testTC6BlanksCollocation() throws {
        let question = try XCTUnwrap(build(.tc6))
        XCTAssertEqual(question.displayText, "_____ fast")
    }

    // MARK: - 機械生成の誤答

    func testMisspellingsAreUniqueAndDifferFromWord() {
        var generator = SeededGenerator(seed: 3)
        let result = ReviewQuestionBuilder.misspellings(of: "receive", count: 3, using: &generator)
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(Set(result).count, 3)
        XCTAssertFalse(result.contains("receive"))
    }

    func testMisspellingsFillShortWords() {
        // 2文字の単語でも3件生成できる（候補不足時は末尾に文字を足して埋める）
        var generator = SeededGenerator(seed: 3)
        let result = ReviewQuestionBuilder.misspellings(of: "go", count: 3, using: &generator)
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(Set(result).count, 3)
        XCTAssertFalse(result.contains("go"))
    }

    func testWrongInflectionFormsExcludeCorrectAndBase() {
        var generator = SeededGenerator(seed: 5)
        let result = ReviewQuestionBuilder.wrongInflectionForms(
            base: "run", correct: "ran", count: 3, using: &generator
        )
        XCTAssertEqual(result.count, 3)
        XCTAssertFalse(result.contains("ran"))
        XCTAssertFalse(result.contains("run"))
    }

    func testTC7RegularVerbDistractorsExcludeCorrectForm() throws {
        // 規則動詞では base+"ed" が正答と一致するため、誤答から除外される
        let info = makeAIInfo(inflections: [.init(form: "過去形", text: "walked")])
        let question = try XCTUnwrap(build(.tc7, material: makeMaterial(text: "walk", aiInfo: info)))
        let answer = try XCTUnwrap(choices(of: question))
        XCTAssertEqual(answer.options.filter { $0 == "walked" }.count, 1)
    }

    // MARK: - 音声系のフォールバック・除外

    func testVC4ExcludesDistractorWordsAppearingInExample() throws {
        // 例文に含まれる語を誤答にすると正解が複数になるため除外される
        let distractors = fullDistractors + [
            ReviewDistractorMaterial(text: "every"), ReviewDistractorMaterial(text: "day"),
        ]
        for seed: UInt64 in 1...5 {
            let question = try XCTUnwrap(build(.vc4, distractors: distractors, seed: seed))
            let answer = try XCTUnwrap(choices(of: question))
            XCTAssertFalse(answer.options.contains("every"))
            XCTAssertFalse(answer.options.contains("day"))
        }
    }

    func testVC5PicksNearestWordsByEditDistance() throws {
        let distractors = [
            ReviewDistractorMaterial(text: "sun"),
            ReviewDistractorMaterial(text: "ruin"),
            ReviewDistractorMaterial(text: "rain"),
            ReviewDistractorMaterial(text: "encyclopedia"),
            ReviewDistractorMaterial(text: "constitution"),
        ]
        let question = try XCTUnwrap(build(.vc5, distractors: distractors))
        let answer = try XCTUnwrap(choices(of: question))
        // 編集距離の近い3語が選ばれ、遠い語は入らない
        XCTAssertFalse(answer.options.contains("encyclopedia"))
        XCTAssertFalse(answer.options.contains("constitution"))
        XCTAssertEqual(answer.options[answer.correctIndex], "run")
    }

    func testAudioFormatsCarryAudioText() throws {
        let question = try XCTUnwrap(build(.vc1))
        XCTAssertEqual(question.audioText, "run")
        XCTAssertNil(question.displayText)

        let dictation = try XCTUnwrap(build(.vt2))
        XCTAssertEqual(dictation.audioText, "I run every day.")
    }

    // MARK: - 素材不足時は nil（呼び出し側でフォールバック）

    func testBuildReturnsNilWhenMaterialInsufficient() {
        let noAIInfo = ReviewWordMaterial(
            text: "run", aiInfo: nil, hasIllustration: false, distractors: .empty
        )
        XCTAssertNil(build(.tc1, material: noAIInfo, distractors: []))
        XCTAssertNil(build(.tc3, material: noAIInfo, distractors: []))
        XCTAssertNil(build(.vt2, material: noAIInfo, distractors: []))

        // 定義はあるが誤答用の他単語が3件未満
        XCTAssertNil(build(.tc1, distractors: Array(fullDistractors.prefix(2))))
    }

    func testSelfContainedFormatsBuildWithoutDistractors() throws {
        // 誤答を機械生成する形式は誤答素材ゼロでも組める
        let textOnly = ReviewWordMaterial(
            text: "run", aiInfo: nil, hasIllustration: false, distractors: .empty
        )
        XCTAssertNotNil(build(.tc9, material: textOnly, distractors: []))
        XCTAssertNotNil(build(.vc2, material: textOnly, distractors: []))
        XCTAssertNotNil(build(.vt1, material: textOnly, distractors: []))
    }

    // MARK: - 誤答の優先度（品詞・CEFR が近いものを優先）

    func testWordDistractorsPreferSamePartOfSpeechAndNearCEFR() throws {
        // 品詞・CEFR が一致する3語 + 遠い3語 → 近い3語が選ばれる
        let near = (1...3).map {
            ReviewDistractorMaterial(text: "near\($0)", partOfSpeechEnglish: "verb", cefrLevel: "A1")
        }
        let far = (1...3).map {
            ReviewDistractorMaterial(text: "far\($0)", partOfSpeechEnglish: "noun", cefrLevel: "C2")
        }
        for seed: UInt64 in 1...5 {
            let question = try XCTUnwrap(build(.tc1, distractors: far + near, seed: seed))
            let answer = try XCTUnwrap(choices(of: question))
            for option in answer.options where option != "run" {
                XCTAssertTrue(option.hasPrefix("near"), "品詞・CEFRの近い語が優先されるべき: \(answer.options)")
            }
        }
    }

    // MARK: - テキスト入力の判定

    func testTypingFormatsAcceptTargetAnswer() throws {
        let cases: [(ReviewQuestionFormat, String)] = [
            (.tt1, "run"), (.tt2, "run"), (.tt3, "ran"), (.it1, "run"), (.vt1, "run"),
        ]
        for (format, expected) in cases {
            let question = try XCTUnwrap(build(format), "\(format)")
            guard case .typing(let spec) = question.answer else {
                return XCTFail("\(format) は typing のはず")
            }
            XCTAssertTrue(ReviewAnswerJudge.isCorrect(input: expected, spec: spec), "\(format)")
        }
    }

    func testNormalizationIgnoresCaseWhitespaceAndPunctuation() {
        let spec = ReviewTypingSpec(acceptedAnswers: ["run"])
        XCTAssertTrue(ReviewAnswerJudge.isCorrect(input: "  Run ", spec: spec))
        XCTAssertTrue(ReviewAnswerJudge.isCorrect(input: "run.", spec: spec))
        XCTAssertFalse(ReviewAnswerJudge.isCorrect(input: "ran", spec: spec))
        XCTAssertFalse(ReviewAnswerJudge.isCorrect(input: "", spec: spec))
        XCTAssertFalse(ReviewAnswerJudge.isCorrect(input: "  ", spec: spec))

        // アポストロフィは保持される（don't ≠ dont は不問にしない）
        let contraction = ReviewTypingSpec(acceptedAnswers: ["don't"])
        XCTAssertTrue(ReviewAnswerJudge.isCorrect(input: "Don’t", spec: contraction))
    }

    func testWordMatchRateForSentences() {
        // 完全一致
        XCTAssertEqual(
            ReviewAnswerJudge.wordMatchRate(input: "I run every day.", reference: "I run every day."),
            1.0
        )
        // 1語欠落（4語中3語一致 = 0.75）
        XCTAssertEqual(
            ReviewAnswerJudge.wordMatchRate(input: "I run day", reference: "I run every day."),
            0.75, accuracy: 0.001
        )
        // 余計な語の挿入も減点される（分母は語数の多い方）
        XCTAssertEqual(
            ReviewAnswerJudge.wordMatchRate(
                input: "I always run every single day", reference: "I run every day."
            ),
            4.0 / 6.0, accuracy: 0.001
        )
    }

    func testVT2JudgesBySentenceMatchRate() throws {
        let question = try XCTUnwrap(build(.vt2))
        guard case .typing(let spec) = question.answer else {
            return XCTFail("vt2 は typing のはず")
        }
        XCTAssertEqual(spec.matchRateThreshold, ReviewQuestionBuilder.sentenceMatchThreshold)
        // 大文字小文字・句読点の違いだけなら正解
        XCTAssertTrue(ReviewAnswerJudge.isCorrect(input: "i run every day", spec: spec))
        // 4語中1語違い（0.75）はしきい値 0.8 未満で不正解
        XCTAssertFalse(ReviewAnswerJudge.isCorrect(input: "i run every night", spec: spec))
    }

    // MARK: - 編集距離

    func testEditDistance() {
        XCTAssertEqual(ReviewQuestionBuilder.editDistance("run", "run"), 0)
        XCTAssertEqual(ReviewQuestionBuilder.editDistance("run", "ran"), 1)
        XCTAssertEqual(ReviewQuestionBuilder.editDistance("run", "rain"), 2)
        XCTAssertEqual(ReviewQuestionBuilder.editDistance("", "run"), 3)
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
