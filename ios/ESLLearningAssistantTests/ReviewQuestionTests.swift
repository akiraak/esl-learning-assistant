import XCTest
@testable import ESLLearningAssistant

/// サーバ保存問題（question_json）のデコードと、テキスト入力回答の判定のテスト。
final class ReviewQuestionTests: XCTestCase {
    private func decode(_ json: String) throws -> ReviewQuestion {
        try JSONDecoder().decode(ReviewQuestion.self, from: Data(json.utf8))
    }

    // MARK: - デコード（サーバ JSON との互換）

    func testDecodeChoicesQuestion() throws {
        let question = try decode("""
        {
          "format": "tc3",
          "instruction": "Choose the word that completes the sentence.",
          "displayText": "She _____ the marathon.",
          "audioText": null,
          "promptIllustrationWord": null,
          "answer": {"type": "choices", "options": ["ran", "walked", "cooked", "slept"],
                     "correctIndex": 0, "acceptedAnswers": null, "matchRateThreshold": null}
        }
        """)
        XCTAssertEqual(question.format, .tc3)
        XCTAssertEqual(question.displayText, "She _____ the marathon.")
        guard case .choices(let options, let correctIndex) = question.answer else {
            return XCTFail("choices のはず")
        }
        XCTAssertEqual(options.count, 4)
        XCTAssertEqual(options[correctIndex], "ran")
    }

    func testDecodeIllustrationChoicesQuestion() throws {
        let question = try decode("""
        {
          "format": "vc8",
          "instruction": "Listen. Which picture shows the word you hear?",
          "displayText": null,
          "audioText": "run",
          "promptIllustrationWord": null,
          "answer": {"type": "illustrationChoices", "options": ["run", "apple", "book", "car"],
                     "correctIndex": 0, "acceptedAnswers": null, "matchRateThreshold": null}
        }
        """)
        XCTAssertEqual(question.audioText, "run")
        guard case .illustrationChoices = question.answer else {
            return XCTFail("illustrationChoices のはず")
        }
    }

    func testDecodeTypingQuestionWithThreshold() throws {
        let question = try decode("""
        {
          "format": "vt2",
          "instruction": "Listen and type the sentence you hear.",
          "displayText": null,
          "audioText": "I run every day.",
          "promptIllustrationWord": null,
          "answer": {"type": "typing", "options": null, "correctIndex": null,
                     "acceptedAnswers": ["I run every day."], "matchRateThreshold": 0.8}
        }
        """)
        guard case .typing(let spec) = question.answer else {
            return XCTFail("typing のはず")
        }
        XCTAssertEqual(spec.acceptedAnswers, ["I run every day."])
        XCTAssertEqual(spec.matchRateThreshold, 0.8)
    }

    func testDecodeRejectsBrokenData() {
        // 未知の形式ID・correctIndex 範囲外・acceptedAnswers 空はデコード段階で弾く
        // （RemoteQuizQuestionService は失敗した問題だけ出題対象から外す）
        let unknownFormat = """
        {"format": "zz9", "instruction": "?", "displayText": null, "audioText": null,
         "promptIllustrationWord": null,
         "answer": {"type": "choices", "options": ["a","b","c","d"], "correctIndex": 0,
                    "acceptedAnswers": null, "matchRateThreshold": null}}
        """
        let outOfRange = """
        {"format": "tc1", "instruction": "?", "displayText": "def", "audioText": null,
         "promptIllustrationWord": null,
         "answer": {"type": "choices", "options": ["a","b","c","d"], "correctIndex": 4,
                    "acceptedAnswers": null, "matchRateThreshold": null}}
        """
        let emptyAccepted = """
        {"format": "vt1", "instruction": "?", "displayText": null, "audioText": "run",
         "promptIllustrationWord": null,
         "answer": {"type": "typing", "options": null, "correctIndex": null,
                    "acceptedAnswers": [], "matchRateThreshold": null}}
        """
        let unknownAnswerType = """
        {"format": "tc1", "instruction": "?", "displayText": "def", "audioText": null,
         "promptIllustrationWord": null,
         "answer": {"type": "speaking", "options": null, "correctIndex": null,
                    "acceptedAnswers": null, "matchRateThreshold": null}}
        """
        for json in [unknownFormat, outOfRange, emptyAccepted, unknownAnswerType] {
            XCTAssertThrowsError(try decode(json), json)
        }
    }

    func testEncodeDecodeRoundTrip() throws {
        let original = ReviewQuestion(
            format: .tt1,
            instruction: "Type the word that matches this definition.",
            displayText: "to move quickly on foot",
            audioText: nil,
            promptIllustrationWord: nil,
            answer: .typing(ReviewTypingSpec(acceptedAnswers: ["run"]))
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ReviewQuestion.self, from: data)
        XCTAssertEqual(decoded.format, .tt1)
        guard case .typing(let spec) = decoded.answer else {
            return XCTFail("typing のはず")
        }
        XCTAssertEqual(spec.acceptedAnswers, ["run"])
        XCTAssertNil(spec.matchRateThreshold)
    }

    // MARK: - テキスト入力の判定（ReviewAnswerJudge）

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

    func testThresholdJudgingForDictation() {
        let spec = ReviewTypingSpec(acceptedAnswers: ["I run every day."], matchRateThreshold: 0.8)
        // 大文字小文字・句読点の違いだけなら正解
        XCTAssertTrue(ReviewAnswerJudge.isCorrect(input: "i run every day", spec: spec))
        // 4語中1語違い（0.75）はしきい値 0.8 未満で不正解
        XCTAssertFalse(ReviewAnswerJudge.isCorrect(input: "i run every night", spec: spec))
    }
}
