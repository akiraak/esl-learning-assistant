import Foundation

/// 復習クイズの出題形式（28形式）。ID 表記: `[出題][回答] + 連番`
/// （T=テキスト, V=音声, I=イラスト, C=4択。一覧: docs/plans/word-memorization-quiz.md §3.3）
enum ReviewQuestionFormat: String, CaseIterable, Codable, Sendable {
    // 出題テキスト・回答4択
    case tc1  // 定義→単語
    case tc2  // 単語→定義
    case tc3  // 例文穴埋め
    case tc4  // 類義語
    case tc5  // 対義語
    case tc6  // コロケーション
    case tc7  // 活用形
    case tc8  // 品詞
    case tc9  // スペリング
    case tc10 // 文中語義（senses 1件の単語に限定）
    case tc11 // 単語→イラスト4択
    // 出題テキスト・回答テキスト入力
    case tt1  // 定義→単語入力
    case tt2  // 例文穴埋め入力
    case tt3  // 活用形入力
    // 出題イラスト
    case ic1  // イラスト→単語4択
    case it1  // イラスト→単語入力
    // 出題音声・回答4択
    case vc1  // 音声→定義
    case vc2  // 音声→綴り
    case vc3  // 定義音声→単語
    case vc4  // 例文リスニング→単語特定
    case vc5  // 類似音判別
    case vc6  // 例文聞き分け
    case vc7  // 活用形リスニング
    case vc8  // 音声→イラスト4択
    // 出題音声+テキスト
    case vtc1 // 例文リスニング穴埋め4択
    case vtt1 // 例文リスニング穴埋め入力
    // 出題音声・回答テキスト入力
    case vt1  // 単語ディクテーション
    case vt2  // 例文ディクテーション（一致率判定）

    /// 出題モダリティの比率枠。複合出題（VTC1・VTT1）は音声側にカウントする
    var promptBucket: ReviewPromptBucket {
        switch self {
        case .tc1, .tc2, .tc3, .tc4, .tc5, .tc6, .tc7, .tc8, .tc9, .tc10, .tc11,
             .tt1, .tt2, .tt3:
            return .text
        case .ic1, .it1:
            return .illustration
        case .vc1, .vc2, .vc3, .vc4, .vc5, .vc6, .vc7, .vc8, .vtc1, .vtt1, .vt1, .vt2:
            return .audio
        }
    }

    /// 回答モダリティの比率枠
    var answerBucket: ReviewAnswerBucket {
        switch self {
        case .tc1, .tc2, .tc3, .tc4, .tc5, .tc6, .tc7, .tc8, .tc9, .tc10,
             .ic1, .vc1, .vc2, .vc3, .vc4, .vc5, .vc6, .vc7, .vtc1:
            return .choice
        case .tt1, .tt2, .tt3, .it1, .vtt1, .vt1, .vt2:
            return .typing
        case .tc11, .vc8:
            return .illustrationChoice
        }
    }
}

enum ReviewPromptBucket: CaseIterable, Sendable {
    case text
    case audio
    case illustration
}

enum ReviewAnswerBucket: CaseIterable, Sendable {
    case choice
    case typing
    case illustrationChoice
}

/// 出題可否の判定に使う、単語1件分の素材と誤答候補プールのスナップショット
struct ReviewWordMaterial {
    var text: String
    /// AI生成情報（未生成なら nil → text だけで組める形式にフォールバック）
    var aiInfo: WordAIInfo?
    /// この単語のイラストが生成済みか
    var hasIllustration: Bool
    var distractors: ReviewDistractorPool
}

/// 誤答選択肢に使える「単語帳内の他の単語」のプール
struct ReviewDistractorPool {
    /// 他の登録単語数（単語テキストを誤答に使う形式用）
    var wordCount: Int
    /// englishDefinition を持つ他単語数（定義を誤答に使う形式用）
    var definitionCount: Int
    /// 例文を持つ他単語数（例文を誤答に使う形式用）
    var exampleCount: Int
    /// イラスト生成済みの他単語数（イラスト4択用）
    var illustrationCount: Int

    static let empty = ReviewDistractorPool(
        wordCount: 0, definitionCount: 0, exampleCount: 0, illustrationCount: 0
    )
}

/// 出題形式の目標比率（docs/plans/word-memorization-quiz.md §3.3「出題形式の選定と比率調整」）
struct FormatRatioTargets: Sendable {
    var prompt: [ReviewPromptBucket: Double]
    var answer: [ReviewAnswerBucket: Double]

    /// v1 既定値: 出題 テキスト50% / 音声50%（イラスト出題10%はテキスト枠から充当 → 実効 40/50/10）、
    /// 回答 4択60% / タイプ入力30% / イラスト4択10%
    static let v1 = FormatRatioTargets(
        prompt: [.text: 0.4, .audio: 0.5, .illustration: 0.1],
        answer: [.choice: 0.6, .typing: 0.3, .illustrationChoice: 0.1]
    )
}

/// 比率調整付きの出題形式選定（純関数）。docs/plans/word-memorization-quiz.md §3.3。
enum FormatSelector {
    /// 4択で誤答選択肢に必要な件数
    static let requiredDistractorCount = 3

    /// 単語の素材から出題可能な形式の集合を返す。
    /// aiInfo 未生成・イラスト未生成・登録語数不足の形式は含まれない（自動フォールバック）。
    static func availableFormats(for material: ReviewWordMaterial) -> Set<ReviewQuestionFormat> {
        Set(ReviewQuestionFormat.allCases.filter { isAvailable($0, for: material) })
    }

    /// セッション実績と目標比率の乖離（不足分）が最大の枠を満たせる形式を選ぶ（貪欲法）。
    /// 出題・回答2軸の不足分の合計をスコアとし、最大スコアの形式から無作為に1つ返す。
    /// 目標枠の形式が組めない場合も残りの形式から選ぶため、比率はベストエフォート。
    static func select(
        availableFormats: Set<ReviewQuestionFormat>,
        sessionCounts: [ReviewQuestionFormat: Int],
        targets: FormatRatioTargets = .v1
    ) -> ReviewQuestionFormat? {
        var generator = SystemRandomNumberGenerator()
        return select(
            availableFormats: availableFormats,
            sessionCounts: sessionCounts,
            targets: targets,
            using: &generator
        )
    }

    static func select<G: RandomNumberGenerator>(
        availableFormats: Set<ReviewQuestionFormat>,
        sessionCounts: [ReviewQuestionFormat: Int],
        targets: FormatRatioTargets = .v1,
        using generator: inout G
    ) -> ReviewQuestionFormat? {
        guard !availableFormats.isEmpty else { return nil }

        let total = sessionCounts.values.reduce(0, +)
        var promptCounts: [ReviewPromptBucket: Int] = [:]
        var answerCounts: [ReviewAnswerBucket: Int] = [:]
        for (format, count) in sessionCounts {
            promptCounts[format.promptBucket, default: 0] += count
            answerCounts[format.answerBucket, default: 0] += count
        }

        // 不足分 = 目標比率 - 実績比率（未出題なら実績0で目標そのもの）
        func deficit(target: Double, count: Int) -> Double {
            let actual = total > 0 ? Double(count) / Double(total) : 0
            return target - actual
        }

        let scored = availableFormats.map { format in
            (
                format: format,
                score: deficit(
                    target: targets.prompt[format.promptBucket] ?? 0,
                    count: promptCounts[format.promptBucket] ?? 0
                ) + deficit(
                    target: targets.answer[format.answerBucket] ?? 0,
                    count: answerCounts[format.answerBucket] ?? 0
                )
            )
        }
        guard let maxScore = scored.map(\.score).max() else { return nil }
        let best = scored.filter { $0.score >= maxScore - 1e-9 }.map(\.format)
        return best.randomElement(using: &generator)
    }

    private static func isAvailable(
        _ format: ReviewQuestionFormat,
        for material: ReviewWordMaterial
    ) -> Bool {
        let info = material.aiInfo
        let pool = material.distractors
        let hasDefinition = info.map { $0.senses.contains { !$0.englishDefinition.isEmpty } } ?? false
        let hasExamples = !(info?.examples.isEmpty ?? true)
        // 全英語の問題文に使えるよう、英語ラベルへ写像できる活用形があるか（TC7・TT3・VC7）
        let hasMappableInflection = info?.inflections.contains {
            GrammarLabelMapping.englishInflectionForm(for: $0.form) != nil
        } ?? false
        // TC8 は先頭の語義（教科書文脈の語義）の品詞が固定4択に写像できる場合のみ
        let posInChoices = info?.senses.first.flatMap {
            GrammarLabelMapping.englishPartOfSpeech(for: $0.partOfSpeech)
        }.map { GrammarLabelMapping.posChoices.contains($0) } ?? false
        let enoughWords = pool.wordCount >= requiredDistractorCount
        let enoughDefinitions = pool.definitionCount >= requiredDistractorCount
        let enoughExamples = pool.exampleCount >= requiredDistractorCount
        let enoughIllustrations = pool.illustrationCount >= requiredDistractorCount

        switch format {
        case .tc1: return hasDefinition && enoughWords
        case .tc2: return hasDefinition && enoughDefinitions
        case .tc3: return hasExamples && enoughWords
        case .tc4: return !(info?.synonyms.isEmpty ?? true) && enoughWords
        case .tc5: return !(info?.antonyms.isEmpty ?? true) && enoughWords
        case .tc6: return !(info?.collocations.isEmpty ?? true) && enoughWords
        case .tc7: return hasMappableInflection // 誤答は規則活用の誤形などを機械生成
        case .tc8: return posInChoices
        case .tc9: return true // 誤答は文字入替・脱字で機械生成（text のみで組める）
        case .tc10: return hasExamples && hasDefinition && info?.senses.count == 1 && enoughDefinitions
        case .tc11: return material.hasIllustration && enoughIllustrations
        case .tt1: return hasDefinition
        case .tt2: return hasExamples
        case .tt3: return hasMappableInflection
        case .ic1: return material.hasIllustration && enoughWords
        case .it1: return material.hasIllustration
        case .vc1: return hasDefinition && enoughDefinitions
        case .vc2: return true // 誤答は類似綴りの他単語 or 機械生成ミススペル
        case .vc3: return hasDefinition && enoughWords
        case .vc4: return hasExamples && enoughWords
        case .vc5: return enoughWords // 発音の近い語は生成時に編集距離で選出
        case .vc6: return hasExamples && enoughExamples
        case .vc7: return hasMappableInflection
        case .vc8: return material.hasIllustration && enoughIllustrations
        case .vtc1: return hasExamples && enoughWords
        case .vtt1: return hasExamples
        case .vt1: return true // text のみで組める
        case .vt2: return hasExamples
        }
    }
}
