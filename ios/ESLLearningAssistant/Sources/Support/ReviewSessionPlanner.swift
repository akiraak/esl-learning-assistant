import Foundation

/// 復習セッションの main キュー分の出題をセッション開始時にまとめて確定する純ロジック
/// （docs/plans/quiz-audio-predownload.md Phase 1）。
/// 事前確定により「このセッションで実際に使う音声」だけを開始前に一括ダウンロードできる。
enum ReviewSessionPlanner {
    struct Plan<ID: Hashable> {
        /// 出題順に確定した (単語ID, 問題)
        var questions: [(wordID: ID, question: ReviewQuestion)]
        /// 確定分を反映した形式カウント（retry 時の比率調整へ引き継ぐ）
        var sessionCounts: [ReviewQuestionFormat: Int]
    }

    /// 出題順に FormatSelector の比率調整で1問ずつ選ぶ。sessionCounts を選択のたびに
    /// 更新するため、出題直前に逐次選択していた従来と同じ形式比率の挙動になる。
    /// 問題が無い・選べない単語はスキップする。
    static func plan<ID: Hashable>(
        wordIDs: [ID],
        questionsByWordID: [ID: [ReviewQuestion]]
    ) -> Plan<ID> {
        var generator = SystemRandomNumberGenerator()
        return plan(wordIDs: wordIDs, questionsByWordID: questionsByWordID, using: &generator)
    }

    static func plan<ID: Hashable, G: RandomNumberGenerator>(
        wordIDs: [ID],
        questionsByWordID: [ID: [ReviewQuestion]],
        using generator: inout G
    ) -> Plan<ID> {
        var counts: [ReviewQuestionFormat: Int] = [:]
        var planned: [(wordID: ID, question: ReviewQuestion)] = []
        for id in wordIDs {
            guard let question = pick(
                from: questionsByWordID[id] ?? [], sessionCounts: counts, using: &generator
            ) else { continue }
            counts[question.format, default: 0] += 1
            planned.append((id, question))
        }
        return Plan(questions: planned, sessionCounts: counts)
    }

    /// 音声ダウンロードに失敗した audioText を含む問題を、同じ単語の別問題へ差し替える。
    /// 差し替え先も音声形式ならローカル音声の存在（hasLocalAudio）を要求する（追加DLはしない）。
    /// 差し替え先が無い単語は出題から外す。
    static func replacingFailedAudio<ID: Hashable>(
        plan: Plan<ID>,
        questionsByWordID: [ID: [ReviewQuestion]],
        failedTexts: Set<String>,
        hasLocalAudio: (String) -> Bool
    ) -> Plan<ID> {
        var generator = SystemRandomNumberGenerator()
        return replacingFailedAudio(
            plan: plan,
            questionsByWordID: questionsByWordID,
            failedTexts: failedTexts,
            hasLocalAudio: hasLocalAudio,
            using: &generator
        )
    }

    static func replacingFailedAudio<ID: Hashable, G: RandomNumberGenerator>(
        plan: Plan<ID>,
        questionsByWordID: [ID: [ReviewQuestion]],
        failedTexts: Set<String>,
        hasLocalAudio: (String) -> Bool,
        using generator: inout G
    ) -> Plan<ID> {
        var counts = plan.sessionCounts
        var questions: [(wordID: ID, question: ReviewQuestion)] = []
        for (id, question) in plan.questions {
            guard let audioText = question.audioText, failedTexts.contains(audioText) else {
                questions.append((id, question))
                continue
            }
            // 差し替え対象。元の形式のカウントを戻してから選び直す
            counts[question.format, default: 1] -= 1
            let candidates = (questionsByWordID[id] ?? []).filter { candidate in
                guard let text = candidate.audioText else { return true }
                return !failedTexts.contains(text) && hasLocalAudio(text)
            }
            guard let replacement = pick(
                from: candidates, sessionCounts: counts, using: &generator
            ) else { continue }
            counts[replacement.format, default: 0] += 1
            questions.append((id, replacement))
        }
        return Plan(questions: questions, sessionCounts: counts)
    }

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
