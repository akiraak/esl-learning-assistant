import Foundation

/// 復習クイズの出題形式（15形式）。ID 表記: `[出題][回答] + 連番`
/// （T=テキスト, V=音声, I=イラスト, C=4択。一覧: docs/plans/archive/word-memorization-quiz.md §3.3、
///   選別: docs/plans/word-quiz-format-curation.md）。
/// rawValue はサーバ保存問題（quiz_questions.format）と一致する。
/// 選別で廃止した形式（tc1/tc8/tc9/tc10/tc11/tt3/vc5/vc6/vc7/vc8/vtc1/vt2）の旧データは
/// デコード失敗として自然に除外される。
enum ReviewQuestionFormat: String, CaseIterable, Codable, Sendable {
    // 出題テキスト・回答4択
    case tc2  // 単語→定義
    case tc3  // 例文穴埋め
    case tc4  // 類義語
    case tc5  // 対義語
    case tc6  // コロケーション
    case tc7  // 活用形
    // 出題テキスト・回答テキスト入力
    case tt1  // 定義→単語入力
    // 出題イラスト
    case ic1  // イラスト→単語4択
    case it1  // イラスト→単語入力
    // 出題音声・回答4択
    case vc1  // 音声→定義
    case vc2  // 音声→綴り
    case vc3  // 定義音声→単語
    case vc4  // 例文リスニング→単語特定
    // 出題音声+テキスト
    case vtt1 // 例文リスニング穴埋め入力（音声が完全文を読むため答えは一意に特定できる）
    // 出題音声・回答テキスト入力
    case vt1  // 単語ディクテーション

    /// 出題モダリティの比率枠。複合出題（VTT1）は音声側にカウントする
    var promptBucket: ReviewPromptBucket {
        switch self {
        case .tc2, .tc3, .tc4, .tc5, .tc6, .tc7, .tt1:
            return .text
        case .ic1, .it1:
            return .illustration
        case .vc1, .vc2, .vc3, .vc4, .vtt1, .vt1:
            return .audio
        }
    }

    /// 回答モダリティの比率枠
    var answerBucket: ReviewAnswerBucket {
        switch self {
        case .tc2, .tc3, .tc4, .tc5, .tc6, .tc7,
             .ic1, .vc1, .vc2, .vc3, .vc4:
            return .choice
        case .tt1, .it1, .vtt1, .vt1:
            return .typing
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

/// 出題形式の目標比率（docs/plans/archive/word-memorization-quiz.md §3.3「出題形式の選定と比率調整」）
struct FormatRatioTargets: Sendable {
    var prompt: [ReviewPromptBucket: Double]
    var answer: [ReviewAnswerBucket: Double]

    /// v1 既定値（15形式版。選別: docs/plans/word-quiz-format-curation.md）:
    /// 出題 テキスト45% / 音声45% / イラスト10%、回答 4択65% / タイプ入力35%
    /// （「絵を選ぶ」回答形式は廃止したため illustrationChoice 枠は設けない）
    static let v1 = FormatRatioTargets(
        prompt: [.text: 0.45, .audio: 0.45, .illustration: 0.1],
        answer: [.choice: 0.65, .typing: 0.35]
    )
}

/// 比率調整付きの出題形式選定（純関数）。docs/plans/archive/word-memorization-quiz.md §3.3。
/// 出題可能な形式の集合はサーバ保存問題の有無で決まる
/// （その単語に保存された問題の形式一覧。docs/plans/archive/quiz-questions-server-storage.md）。
enum FormatSelector {
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
}
