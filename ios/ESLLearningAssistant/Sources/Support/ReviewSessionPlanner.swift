import Foundation

/// 復習セッションの出題選択ロジック。
/// 習熟度方式（docs/plans/archive/review-mastery-progress.md）では出題順が解答結果に依存して
/// 動的に決まるため、事前確定（plan / replacingFailedAudio）は廃止し、
/// 1問ずつの形式選択（pick）のみを提供する。
enum ReviewSessionPlanner {
    /// FormatSelector で形式を選び、同形式の複数バリエーションからランダムに1問返す
    static func pick(
        from questions: [ReviewQuestion],
        sessionCounts: [ReviewQuestionFormat: Int]
    ) -> ReviewQuestion? {
        var generator = SystemRandomNumberGenerator()
        return pick(from: questions, sessionCounts: sessionCounts, using: &generator)
    }

    static func pick<G: RandomNumberGenerator>(
        from questions: [ReviewQuestion],
        sessionCounts: [ReviewQuestionFormat: Int],
        using generator: inout G
    ) -> ReviewQuestion? {
        guard !questions.isEmpty else { return nil }
        guard let format = FormatSelector.select(
            availableFormats: Set(questions.map(\.format)),
            sessionCounts: sessionCounts,
            using: &generator
        ) else { return nil }
        return questions.filter { $0.format == format }.randomElement(using: &generator)
    }
}
