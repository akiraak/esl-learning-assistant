import Foundation

// MARK: - 問題データ

/// 組み立て済みの復習クイズ1問（純データ）。
/// 音声・イラストのファイル解決や再生は View 側で行う。
/// docs/plans/word-memorization-quiz.md §3.3 の28形式に対応する。
struct ReviewQuestion {
    var format: ReviewQuestionFormat
    /// 画面上部に表示する英語の指示文
    var instruction: String
    /// 表示する本文（英語定義・空所つき例文など）。音声のみの出題では nil
    var displayText: String?
    /// 再生する音声のテキスト（音声出題形式のみ。TTS / 内蔵読み上げの対象）
    var audioText: String?
    /// 出題として表示するイラストの単語（IC1・IT1）
    var promptIllustrationWord: String?
    var answer: ReviewQuestionAnswer
}

enum ReviewQuestionAnswer {
    /// テキスト4択（options はシャッフル済み）
    case choices(options: [String], correctIndex: Int)
    /// イラスト4択（要素は各単語のテキスト。イラストの解決は View 側）
    case illustrationChoices(options: [String], correctIndex: Int)
    /// テキスト入力
    case typing(ReviewTypingSpec)
}

/// テキスト入力回答の判定仕様（判定は ReviewAnswerJudge）
struct ReviewTypingSpec {
    /// 正規化後にこのいずれかと一致すれば正解
    var acceptedAnswers: [String]
    /// VT2（例文ディクテーション）の単語一致率しきい値。nil なら完全一致
    var matchRateThreshold: Double?

    init(acceptedAnswers: [String], matchRateThreshold: Double? = nil) {
        self.acceptedAnswers = acceptedAnswers
        self.matchRateThreshold = matchRateThreshold
    }
}

/// 誤答選択肢の素材にする、単語帳内の他単語1件分のスナップショット
struct ReviewDistractorMaterial {
    var text: String
    /// 先頭語義の英語定義（無ければ nil）
    var englishDefinition: String?
    /// 先頭の例文（無ければ nil）
    var example: String?
    var hasIllustration: Bool
    /// 先頭語義の品詞（英語ラベル）。品詞が近い単語を誤答に優先するために使う
    var partOfSpeechEnglish: String?
    var cefrLevel: String?

    init(
        text: String,
        englishDefinition: String? = nil,
        example: String? = nil,
        hasIllustration: Bool = false,
        partOfSpeechEnglish: String? = nil,
        cefrLevel: String? = nil
    ) {
        self.text = text
        self.englishDefinition = englishDefinition
        self.example = example
        self.hasIllustration = hasIllustration
        self.partOfSpeechEnglish = partOfSpeechEnglish
        self.cefrLevel = cefrLevel
    }
}

extension ReviewDistractorPool {
    /// 誤答素材のスナップショットから FormatSelector 用の件数プールを作る
    init(materials: [ReviewDistractorMaterial]) {
        self.init(
            wordCount: materials.count,
            definitionCount: materials.filter { !($0.englishDefinition ?? "").isEmpty }.count,
            exampleCount: materials.filter { !($0.example ?? "").isEmpty }.count,
            illustrationCount: materials.filter(\.hasIllustration).count
        )
    }
}

// MARK: - 問題組み立て

/// 形式・単語素材・誤答素材から1問を組み立てる純関数。
/// FormatSelector.availableFormats が通した形式でも、実データの噛み合わせ
/// （例文中に対象語が現れない等）で組めない場合は nil を返す（呼び出し側で別形式へフォールバック）。
enum ReviewQuestionBuilder {
    /// 4択の選択肢数
    static let choiceCount = 4
    /// VT2（例文ディクテーション）の単語一致率しきい値
    static let sentenceMatchThreshold = 0.8

    static func build(
        format: ReviewQuestionFormat,
        material: ReviewWordMaterial,
        distractors: [ReviewDistractorMaterial]
    ) -> ReviewQuestion? {
        var generator = SystemRandomNumberGenerator()
        return build(format: format, material: material, distractors: distractors, using: &generator)
    }

    static func build<G: RandomNumberGenerator>(
        format: ReviewQuestionFormat,
        material: ReviewWordMaterial,
        distractors: [ReviewDistractorMaterial],
        using generator: inout G
    ) -> ReviewQuestion? {
        let word = material.text
        let info = material.aiInfo

        switch format {
        case .tc1:
            guard let definition = firstDefinition(of: info) else { return nil }
            guard let answer = wordChoiceAnswer(
                correct: word, material: material, distractors: distractors, using: &generator
            ) else { return nil }
            return ReviewQuestion(
                format: format,
                instruction: "Which word matches this definition?",
                displayText: definition,
                audioText: nil,
                promptIllustrationWord: nil,
                answer: answer
            )

        case .tc2:
            guard let definition = firstDefinition(of: info) else { return nil }
            guard let answer = definitionChoiceAnswer(
                correct: definition, material: material, distractors: distractors, using: &generator
            ) else { return nil }
            return ReviewQuestion(
                format: format,
                instruction: "Which is the correct definition of “\(word)”?",
                displayText: nil,
                audioText: nil,
                promptIllustrationWord: nil,
                answer: answer
            )

        case .tc3:
            guard let blanked = blankedExample(for: material) else { return nil }
            guard let answer = tokenChoiceAnswer(
                correctToken: blanked.token, material: material, distractors: distractors, using: &generator
            ) else { return nil }
            return ReviewQuestion(
                format: format,
                instruction: "Choose the word that completes the sentence.",
                displayText: blanked.display,
                audioText: nil,
                promptIllustrationWord: nil,
                answer: answer
            )

        case .tc4:
            guard let synonym = info?.synonyms.filter({ !$0.isEmpty }).randomElement(using: &generator)
            else { return nil }
            // 別の類義語が誤答に混ざると正解が複数になるため、類義語と本体は除外する
            let excluded = excludedKeys(word: word, extra: info?.synonyms ?? [])
            guard let answer = choiceAnswer(
                correct: synonym,
                wrong: prioritizedValues(
                    from: distractors, value: { $0.text }, excludingKeys: excluded,
                    material: material, using: &generator
                ),
                using: &generator
            ) else { return nil }
            return ReviewQuestion(
                format: format,
                instruction: "Which is closest in meaning to “\(word)”?",
                displayText: nil,
                audioText: nil,
                promptIllustrationWord: nil,
                answer: answer
            )

        case .tc5:
            guard let antonym = info?.antonyms.filter({ !$0.isEmpty }).randomElement(using: &generator)
            else { return nil }
            // 別の対義語が誤答に混ざると正解が複数になるため、対義語と本体は除外する
            let excluded = excludedKeys(word: word, extra: info?.antonyms ?? [])
            guard let answer = choiceAnswer(
                correct: antonym,
                wrong: prioritizedValues(
                    from: distractors, value: { $0.text }, excludingKeys: excluded,
                    material: material, using: &generator
                ),
                using: &generator
            ) else { return nil }
            return ReviewQuestion(
                format: format,
                instruction: "Which is the opposite of “\(word)”?",
                displayText: nil,
                audioText: nil,
                promptIllustrationWord: nil,
                answer: answer
            )

        case .tc6:
            guard let blanked = blankedCollocation(for: material) else { return nil }
            guard let answer = tokenChoiceAnswer(
                correctToken: blanked.token, material: material, distractors: distractors, using: &generator
            ) else { return nil }
            return ReviewQuestion(
                format: format,
                instruction: "Choose the word that completes the phrase.",
                displayText: blanked.display,
                audioText: nil,
                promptIllustrationWord: nil,
                answer: answer
            )

        case .tc7:
            guard let inflection = mappableInflection(of: info) else { return nil }
            let wrong = wrongInflectionForms(
                base: word, correct: inflection.text, count: choiceCount - 1, using: &generator
            )
            guard let answer = choiceAnswer(correct: inflection.text, wrong: wrong, using: &generator)
            else { return nil }
            return ReviewQuestion(
                format: format,
                instruction: "What is the \(inflection.formEnglish) of “\(word)”?",
                displayText: nil,
                audioText: nil,
                promptIllustrationWord: nil,
                answer: answer
            )

        case .tc8:
            guard let pos = info?.senses.first.flatMap({
                GrammarLabelMapping.englishPartOfSpeech(for: $0.partOfSpeech)
            }), GrammarLabelMapping.posChoices.contains(pos) else { return nil }
            // 品詞は固定4択（シャッフルせず定番の並びで出す）
            let options = ["noun", "verb", "adjective", "adverb"]
            guard let correctIndex = options.firstIndex(of: pos) else { return nil }
            return ReviewQuestion(
                format: format,
                instruction: "“\(word)” is a …",
                displayText: nil,
                audioText: nil,
                promptIllustrationWord: nil,
                answer: .choices(options: options, correctIndex: correctIndex)
            )

        case .tc9:
            let wrong = misspellings(of: word, count: choiceCount - 1, using: &generator)
            guard let answer = choiceAnswer(correct: word, wrong: wrong, using: &generator)
            else { return nil }
            return ReviewQuestion(
                format: format,
                instruction: "Which spelling is correct?",
                displayText: nil,
                audioText: nil,
                promptIllustrationWord: nil,
                answer: answer
            )

        case .tc10:
            // v1 は senses が1件の単語に限定（FormatSelector と同条件）
            guard info?.senses.count == 1, let definition = firstDefinition(of: info),
                  let example = exampleContainingTarget(material)
            else { return nil }
            guard let answer = definitionChoiceAnswer(
                correct: definition, material: material, distractors: distractors, using: &generator
            ) else { return nil }
            return ReviewQuestion(
                format: format,
                instruction: "What does “\(word)” mean in this sentence?",
                displayText: example,
                audioText: nil,
                promptIllustrationWord: nil,
                answer: answer
            )

        case .tc11:
            guard material.hasIllustration else { return nil }
            guard let answer = illustrationChoiceAnswer(
                material: material, distractors: distractors, using: &generator
            ) else { return nil }
            return ReviewQuestion(
                format: format,
                instruction: "Which picture shows “\(word)”?",
                displayText: nil,
                audioText: nil,
                promptIllustrationWord: nil,
                answer: answer
            )

        case .tt1:
            guard let definition = firstDefinition(of: info) else { return nil }
            return ReviewQuestion(
                format: format,
                instruction: "Type the word that matches this definition.",
                displayText: definition,
                audioText: nil,
                promptIllustrationWord: nil,
                answer: .typing(ReviewTypingSpec(acceptedAnswers: [word]))
            )

        case .tt2:
            guard let blanked = blankedExample(for: material) else { return nil }
            return ReviewQuestion(
                format: format,
                instruction: "Type the word that completes the sentence.",
                displayText: blanked.display,
                audioText: nil,
                promptIllustrationWord: nil,
                answer: .typing(ReviewTypingSpec(acceptedAnswers: [blanked.token]))
            )

        case .tt3:
            guard let inflection = mappableInflection(of: info) else { return nil }
            return ReviewQuestion(
                format: format,
                instruction: "Type the \(inflection.formEnglish) of “\(word)”.",
                displayText: nil,
                audioText: nil,
                promptIllustrationWord: nil,
                answer: .typing(ReviewTypingSpec(acceptedAnswers: [inflection.text]))
            )

        case .ic1:
            guard material.hasIllustration else { return nil }
            guard let answer = wordChoiceAnswer(
                correct: word, material: material, distractors: distractors, using: &generator
            ) else { return nil }
            return ReviewQuestion(
                format: format,
                instruction: "Which word does this picture show?",
                displayText: nil,
                audioText: nil,
                promptIllustrationWord: word,
                answer: answer
            )

        case .it1:
            guard material.hasIllustration else { return nil }
            return ReviewQuestion(
                format: format,
                instruction: "Type the word this picture shows.",
                displayText: nil,
                audioText: nil,
                promptIllustrationWord: word,
                answer: .typing(ReviewTypingSpec(acceptedAnswers: [word]))
            )

        case .vc1:
            guard let definition = firstDefinition(of: info) else { return nil }
            guard let answer = definitionChoiceAnswer(
                correct: definition, material: material, distractors: distractors, using: &generator
            ) else { return nil }
            return ReviewQuestion(
                format: format,
                instruction: "Listen. Which is the correct definition of the word you hear?",
                displayText: nil,
                audioText: word,
                promptIllustrationWord: nil,
                answer: answer
            )

        case .vc2:
            let wrong = misspellings(of: word, count: choiceCount - 1, using: &generator)
            guard let answer = choiceAnswer(correct: word, wrong: wrong, using: &generator)
            else { return nil }
            return ReviewQuestion(
                format: format,
                instruction: "Listen. Choose the correct spelling.",
                displayText: nil,
                audioText: word,
                promptIllustrationWord: nil,
                answer: answer
            )

        case .vc3:
            guard let definition = firstDefinition(of: info) else { return nil }
            guard let answer = wordChoiceAnswer(
                correct: word, material: material, distractors: distractors, using: &generator
            ) else { return nil }
            return ReviewQuestion(
                format: format,
                instruction: "Listen to the definition. Which word does it describe?",
                displayText: nil,
                audioText: definition,
                promptIllustrationWord: nil,
                answer: answer
            )

        case .vc4:
            guard let example = exampleContainingTarget(material) else { return nil }
            // 例文中に現れる語を誤答にすると「聞こえた単語」が複数正解になるため除外する
            let wrong = prioritizedValues(
                from: distractors.filter { !containsToken($0.text, in: example) },
                value: { $0.text },
                excludingKeys: excludedKeys(word: word, extra: inflectionTexts(of: info)),
                material: material,
                using: &generator
            )
            guard let answer = choiceAnswer(correct: word, wrong: wrong, using: &generator)
            else { return nil }
            return ReviewQuestion(
                format: format,
                instruction: "Listen to the sentence. Which word do you hear?",
                displayText: nil,
                audioText: example,
                promptIllustrationWord: nil,
                answer: answer
            )

        case .vc5:
            // 発音の近い語 ≒ 綴りの近い語として、編集距離の小さい順に誤答を選ぶ
            let excluded = excludedKeys(word: word, extra: inflectionTexts(of: info))
            let candidates = distractors
                .map(\.text)
                .filter { !excluded.contains(choiceKey($0)) }
            let sorted = candidates.sorted {
                editDistance($0.lowercased(), word.lowercased())
                    < editDistance($1.lowercased(), word.lowercased())
            }
            guard let answer = choiceAnswer(correct: word, wrong: sorted, using: &generator)
            else { return nil }
            return ReviewQuestion(
                format: format,
                instruction: "Listen carefully. Which word do you hear?",
                displayText: nil,
                audioText: word,
                promptIllustrationWord: nil,
                answer: answer
            )

        case .vc6:
            guard let example = firstExample(of: info) else { return nil }
            let wrong = prioritizedValues(
                from: distractors, value: { $0.example },
                excludingKeys: [choiceKey(example)],
                material: material,
                using: &generator
            )
            guard let answer = choiceAnswer(correct: example, wrong: wrong, using: &generator)
            else { return nil }
            return ReviewQuestion(
                format: format,
                instruction: "Listen. Which sentence do you hear?",
                displayText: nil,
                audioText: example,
                promptIllustrationWord: nil,
                answer: answer
            )

        case .vc7:
            guard let inflection = mappableInflection(of: info) else { return nil }
            let wrongLabels = inflectionFormLabels
                .filter { $0 != inflection.formEnglish }
                .shuffled(using: &generator)
            guard let answer = choiceAnswer(
                correct: inflection.formEnglish, wrong: wrongLabels, using: &generator
            ) else { return nil }
            return ReviewQuestion(
                format: format,
                instruction: "Listen. Which form of “\(word)” do you hear?",
                displayText: nil,
                audioText: inflection.text,
                promptIllustrationWord: nil,
                answer: answer
            )

        case .vc8:
            guard material.hasIllustration else { return nil }
            guard let answer = illustrationChoiceAnswer(
                material: material, distractors: distractors, using: &generator
            ) else { return nil }
            return ReviewQuestion(
                format: format,
                instruction: "Listen. Which picture shows the word you hear?",
                displayText: nil,
                audioText: word,
                promptIllustrationWord: nil,
                answer: answer
            )

        case .vtc1:
            guard let blanked = blankedExample(for: material) else { return nil }
            guard let answer = tokenChoiceAnswer(
                correctToken: blanked.token, material: material, distractors: distractors, using: &generator
            ) else { return nil }
            return ReviewQuestion(
                format: format,
                instruction: "Listen and choose the word that completes the sentence.",
                displayText: blanked.display,
                audioText: blanked.full,
                promptIllustrationWord: nil,
                answer: answer
            )

        case .vtt1:
            guard let blanked = blankedExample(for: material) else { return nil }
            return ReviewQuestion(
                format: format,
                instruction: "Listen and type the missing word.",
                displayText: blanked.display,
                audioText: blanked.full,
                promptIllustrationWord: nil,
                answer: .typing(ReviewTypingSpec(acceptedAnswers: [blanked.token]))
            )

        case .vt1:
            return ReviewQuestion(
                format: format,
                instruction: "Listen and type the word you hear.",
                displayText: nil,
                audioText: word,
                promptIllustrationWord: nil,
                answer: .typing(ReviewTypingSpec(acceptedAnswers: [word]))
            )

        case .vt2:
            guard let example = firstExample(of: info) else { return nil }
            return ReviewQuestion(
                format: format,
                instruction: "Listen and type the sentence you hear.",
                displayText: nil,
                audioText: example,
                promptIllustrationWord: nil,
                answer: .typing(ReviewTypingSpec(
                    acceptedAnswers: [example],
                    matchRateThreshold: sentenceMatchThreshold
                ))
            )
        }
    }

    // MARK: - 素材の取り出し

    private static func firstDefinition(of info: WordAIInfo?) -> String? {
        info?.senses.first(where: { !$0.englishDefinition.isEmpty })?.englishDefinition
    }

    private static func firstExample(of info: WordAIInfo?) -> String? {
        info?.examples.first(where: { !$0.english.isEmpty })?.english
    }

    private static func inflectionTexts(of info: WordAIInfo?) -> [String] {
        info?.inflections.map(\.text) ?? []
    }

    /// 英語ラベルへ写像できる最初の活用形
    private static func mappableInflection(of info: WordAIInfo?) -> (formEnglish: String, text: String)? {
        for inflection in info?.inflections ?? [] {
            if let form = GrammarLabelMapping.englishInflectionForm(for: inflection.form),
               !inflection.text.isEmpty {
                return (form, inflection.text)
            }
        }
        return nil
    }

    /// VC7 の選択肢に使う活用形ラベルの全集合（マッピングの英語ラベル + base form）
    private static let inflectionFormLabels: [String] =
        (Set(GrammarLabelMapping.inflectionForm.values).union(["base form"])).sorted()

    /// 対象語（本体または活用形）を含む最初の例文
    private static func exampleContainingTarget(_ material: ReviewWordMaterial) -> String? {
        let tokens = [material.text] + inflectionTexts(of: material.aiInfo)
        for example in material.aiInfo?.examples ?? [] {
            if tokens.contains(where: { containsToken($0, in: example.english) }) {
                return example.english
            }
        }
        return nil
    }

    /// 例文中の対象語（本体または活用形。本体を優先）を "_____" に置換する
    private static func blankedExample(
        for material: ReviewWordMaterial
    ) -> (display: String, token: String, full: String)? {
        blanked(texts: material.aiInfo?.examples.map(\.english) ?? [], material: material)
    }

    /// コロケーション中の対象語を "_____" に置換する（"make a decision" → "make a _____"）
    private static func blankedCollocation(
        for material: ReviewWordMaterial
    ) -> (display: String, token: String, full: String)? {
        blanked(texts: material.aiInfo?.collocations ?? [], material: material)
    }

    private static func blanked(
        texts: [String],
        material: ReviewWordMaterial
    ) -> (display: String, token: String, full: String)? {
        let tokens = [material.text] + inflectionTexts(of: material.aiInfo)
        for text in texts {
            for token in tokens where !token.isEmpty {
                guard let range = rangeOfToken(token, in: text) else { continue }
                let matched = String(text[range])
                var display = text
                display.replaceSubrange(range, with: "_____")
                return (display, matched, text)
            }
        }
        return nil
    }

    private static func rangeOfToken(_ token: String, in text: String) -> Range<String.Index>? {
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: token))\\b"
        return text.range(of: pattern, options: [.regularExpression, .caseInsensitive])
    }

    private static func containsToken(_ token: String, in text: String) -> Bool {
        rangeOfToken(token, in: text) != nil
    }

    // MARK: - 選択肢の組み立て

    /// 誤答候補（優先度順）と正答から4択を組む。重複を除いた誤答が3件に満たなければ nil
    private static func choiceAnswer<G: RandomNumberGenerator>(
        correct: String,
        wrong: [String],
        using generator: inout G
    ) -> ReviewQuestionAnswer? {
        guard let (options, correctIndex) = choiceOptions(correct: correct, wrong: wrong, using: &generator)
        else { return nil }
        return .choices(options: options, correctIndex: correctIndex)
    }

    private static func choiceOptions<G: RandomNumberGenerator>(
        correct: String,
        wrong: [String],
        using generator: inout G
    ) -> (options: [String], correctIndex: Int)? {
        var seen: Set<String> = [choiceKey(correct)]
        var picked: [String] = []
        for candidate in wrong where picked.count < choiceCount - 1 {
            let key = choiceKey(candidate)
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            picked.append(candidate)
        }
        guard picked.count == choiceCount - 1 else { return nil }
        var options = picked + [correct]
        options.shuffle(using: &generator)
        guard let correctIndex = options.firstIndex(of: correct) else { return nil }
        return (options, correctIndex)
    }

    /// 選択肢の重複判定に使うキー（正規化後の文字列）
    private static func choiceKey(_ text: String) -> String {
        ReviewAnswerJudge.normalize(text)
    }

    private static func excludedKeys(word: String, extra: [String] = []) -> Set<String> {
        Set(([word] + extra).map(choiceKey))
    }

    /// 正答が単語本体の4択（誤答は他単語のテキスト。品詞・CEFR が近いものを優先）
    private static func wordChoiceAnswer<G: RandomNumberGenerator>(
        correct: String,
        material: ReviewWordMaterial,
        distractors: [ReviewDistractorMaterial],
        using generator: inout G
    ) -> ReviewQuestionAnswer? {
        let wrong = prioritizedValues(
            from: distractors, value: { $0.text },
            excludingKeys: excludedKeys(word: material.text, extra: inflectionTexts(of: material.aiInfo)),
            material: material,
            using: &generator
        )
        return choiceAnswer(correct: correct, wrong: wrong, using: &generator)
    }

    /// 例文・コロケーションの空所に入るトークンが正答の4択
    private static func tokenChoiceAnswer<G: RandomNumberGenerator>(
        correctToken: String,
        material: ReviewWordMaterial,
        distractors: [ReviewDistractorMaterial],
        using generator: inout G
    ) -> ReviewQuestionAnswer? {
        let wrong = prioritizedValues(
            from: distractors, value: { $0.text },
            excludingKeys: excludedKeys(word: material.text, extra: inflectionTexts(of: material.aiInfo)),
            material: material,
            using: &generator
        )
        return choiceAnswer(correct: correctToken, wrong: wrong, using: &generator)
    }

    /// 正答が英語定義の4択（誤答は他単語の定義）
    private static func definitionChoiceAnswer<G: RandomNumberGenerator>(
        correct: String,
        material: ReviewWordMaterial,
        distractors: [ReviewDistractorMaterial],
        using generator: inout G
    ) -> ReviewQuestionAnswer? {
        let wrong = prioritizedValues(
            from: distractors, value: { $0.englishDefinition },
            excludingKeys: [choiceKey(correct)],
            material: material,
            using: &generator
        )
        return choiceAnswer(correct: correct, wrong: wrong, using: &generator)
    }

    /// イラスト4択（正答は単語本体、誤答はイラスト生成済みの他単語）
    private static func illustrationChoiceAnswer<G: RandomNumberGenerator>(
        material: ReviewWordMaterial,
        distractors: [ReviewDistractorMaterial],
        using generator: inout G
    ) -> ReviewQuestionAnswer? {
        let wrong = prioritizedValues(
            from: distractors, value: { $0.hasIllustration ? $0.text : nil },
            excludingKeys: excludedKeys(word: material.text),
            material: material,
            using: &generator
        )
        guard let (options, correctIndex) = choiceOptions(
            correct: material.text, wrong: wrong, using: &generator
        ) else { return nil }
        return .illustrationChoices(options: options, correctIndex: correctIndex)
    }

    /// 誤答候補を「品詞が同じ > CEFR が近い」の優先度でソートして返す（同順位はシャッフル順）。
    /// docs/plans/word-memorization-quiz.md §3.3「誤答は品詞・CEFR が近いものを優先」。
    private static func prioritizedValues<G: RandomNumberGenerator>(
        from distractors: [ReviewDistractorMaterial],
        value: (ReviewDistractorMaterial) -> String?,
        excludingKeys: Set<String>,
        material: ReviewWordMaterial,
        using generator: inout G
    ) -> [String] {
        let targetPOS = material.aiInfo?.senses.first.flatMap {
            GrammarLabelMapping.englishPartOfSpeech(for: $0.partOfSpeech)
        }
        let targetCEFR = cefrIndex(material.aiInfo?.cefrLevel)

        let candidates: [(value: String, score: Double)] = distractors.compactMap { distractor in
            guard let text = value(distractor), !text.isEmpty,
                  !excludingKeys.contains(choiceKey(text)) else { return nil }
            var score = 0.0
            if let targetPOS, let pos = distractor.partOfSpeechEnglish {
                score += pos == targetPOS ? 0 : 1
            } else {
                score += 0.5 // 品詞不明はどちらとも言えない中間扱い
            }
            if let targetCEFR, let cefr = cefrIndex(distractor.cefrLevel) {
                score += Double(abs(targetCEFR - cefr)) * 0.1
            } else {
                score += 0.25
            }
            return (text, score)
        }
        return candidates
            .shuffled(using: &generator)
            .sorted { $0.score < $1.score }
            .map(\.value)
    }

    private static func cefrIndex(_ level: String?) -> Int? {
        guard let level else { return nil }
        let order = ["A1", "A2", "B1", "B2", "C1", "C2"]
        return order.firstIndex(of: level.trimmingCharacters(in: .whitespaces).uppercased())
    }

    // MARK: - 機械生成の誤答

    /// 文字入替・脱字・重複でミススペルを生成する（TC9・VC2）。
    /// 実在語の混入を避けるため母音置換などの「読める変形」は行わない。
    static func misspellings<G: RandomNumberGenerator>(
        of word: String,
        count: Int,
        using generator: inout G
    ) -> [String] {
        let chars = Array(word)
        var candidates: Set<String> = []

        // 隣接文字の入替
        for i in 0..<max(chars.count - 1, 0) where chars[i] != chars[i + 1] {
            var swapped = chars
            swapped.swapAt(i, i + 1)
            candidates.insert(String(swapped))
        }
        // 1文字の脱字
        if chars.count >= 3 {
            for i in chars.indices {
                var dropped = chars
                dropped.remove(at: i)
                candidates.insert(String(dropped))
            }
        }
        // 1文字の重複
        for i in chars.indices where chars[i].isLetter {
            var doubled = chars
            doubled.insert(chars[i], at: i)
            candidates.insert(String(doubled))
        }

        let key = choiceKey(word)
        var result = candidates
            .filter { choiceKey($0) != key }
            .shuffled(using: &generator)

        // 短い単語などで候補が足りない場合は末尾に文字を足して埋める
        var filler = word
        while result.count < count {
            filler += "h"
            if choiceKey(filler) != key, !result.contains(filler) {
                result.append(filler)
            }
        }
        return Array(result.prefix(count))
    }

    /// 規則活用の誤形などを機械生成する（TC7 の誤答）
    static func wrongInflectionForms<G: RandomNumberGenerator>(
        base: String,
        correct: String,
        count: Int,
        using generator: inout G
    ) -> [String] {
        var doubledFinal = base
        if let last = base.last, last.isLetter {
            doubledFinal += String(last)
        }
        let candidates = [
            base + "ed", base + "d", doubledFinal + "ed",
            base + "s", base + "es",
            base + "ing", doubledFinal + "ing",
            base + "er", base + "est",
        ]
        let excluded = Set([base, correct].map(choiceKey))
        var seen: Set<String> = []
        var result: [String] = []
        for candidate in candidates.shuffled(using: &generator) {
            let key = choiceKey(candidate)
            guard !excluded.contains(key), !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(candidate)
        }
        if result.count < count {
            // 補いはミススペル（correct の変形）から取る
            for candidate in misspellings(of: correct, count: count, using: &generator) {
                let key = choiceKey(candidate)
                guard !excluded.contains(key), !seen.contains(key) else { continue }
                seen.insert(key)
                result.append(candidate)
                if result.count >= count { break }
            }
        }
        return Array(result.prefix(count))
    }

    /// レーベンシュタイン編集距離（VC5 の類似音選出用）
    static func editDistance(_ a: String, _ b: String) -> Int {
        let s = Array(a), t = Array(b)
        if s.isEmpty { return t.count }
        if t.isEmpty { return s.count }
        var previous = Array(0...t.count)
        var current = [Int](repeating: 0, count: t.count + 1)
        for i in 1...s.count {
            current[0] = i
            for j in 1...t.count {
                let cost = s[i - 1] == t[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            swap(&previous, &current)
        }
        return previous[t.count]
    }
}

// MARK: - テキスト入力回答の判定

/// テキスト入力（TT / IT / VTT / VT 系）の判定。docs/plans/word-memorization-quiz.md §5。
enum ReviewAnswerJudge {
    /// 小文字化・前後空白除去・句読点除去（単語内のアポストロフィは保持）・空白の圧縮
    static func normalize(_ text: String) -> String {
        let lowered = text.lowercased().replacingOccurrences(of: "’", with: "'")
        let punctuation = CharacterSet.punctuationCharacters.subtracting(CharacterSet(charactersIn: "'"))
        let scalars = lowered.unicodeScalars.map { punctuation.contains($0) ? " " as UnicodeScalar : $0 }
        return String(String.UnicodeScalarView(scalars))
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    /// 入力が仕様の正解に一致するか。matchRateThreshold があれば単語一致率で判定する
    static func isCorrect(input: String, spec: ReviewTypingSpec) -> Bool {
        let normalizedInput = normalize(input)
        guard !normalizedInput.isEmpty else { return false }
        if let threshold = spec.matchRateThreshold {
            return spec.acceptedAnswers.contains {
                wordMatchRate(input: normalizedInput, reference: $0) >= threshold
            }
        }
        return spec.acceptedAnswers.contains { normalize($0) == normalizedInput }
    }

    /// 単語単位の一致率（LCS 長 / 単語数の多い方）。挿入・欠落・置換をまとめて減点する
    static func wordMatchRate(input: String, reference: String) -> Double {
        let a = normalize(input).split(separator: " ").map(String.init)
        let b = normalize(reference).split(separator: " ").map(String.init)
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        var previous = [Int](repeating: 0, count: b.count + 1)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            for j in 1...b.count {
                current[j] = a[i - 1] == b[j - 1]
                    ? previous[j - 1] + 1
                    : max(previous[j], current[j - 1])
            }
            swap(&previous, &current)
            current = [Int](repeating: 0, count: b.count + 1)
        }
        return Double(previous[b.count]) / Double(max(a.count, b.count))
    }
}
