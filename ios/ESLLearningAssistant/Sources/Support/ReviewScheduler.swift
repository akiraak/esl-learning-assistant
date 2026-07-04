import Foundation

/// 単語復習の間隔反復スケジューラ（固定ステップの Leitner 方式）。
/// docs/specs/data-model.md §5 / docs/plans/archive/word-memorization-quiz.md §3.1。
/// SM-2 / FSRS への将来差し替えを想定し、モデルから分離した純関数として実装する。
enum ReviewScheduler {
    /// 復習ステップの間隔（日）。最終ステップ到達後は90日間隔を維持する。
    static let stepIntervalsInDays = [3, 7, 14, 30, 90]

    /// 1回の解答結果を反映した新しい復習状態を返す。
    /// - 正解: 現在ステップの間隔で次回日を設定し、ステップを1つ進める（最終ステップでは維持）
    /// - 不正解: ステップを0に戻し、step 0 の間隔（3日）で次回日を設定する
    ///   （同日中の再出題はセッション内でのみ行い、dueDate には反映しない）
    static func reviewed(
        _ state: WordReviewState,
        isCorrect: Bool,
        at now: Date = .now,
        calendar: Calendar = .current
    ) -> WordReviewState {
        var next = state
        next.lastReviewedAt = now
        next.reviewCount += 1
        if isCorrect {
            let step = clampedStep(state.stepIndex)
            next.correctCount += 1
            next.stepIndex = min(step + 1, stepIntervalsInDays.count - 1)
            next.dueDate = dueDate(inDays: stepIntervalsInDays[step], from: now, calendar: calendar)
        } else {
            next.lapseCount += 1
            next.stepIndex = 0
            next.dueDate = dueDate(inDays: stepIntervalsInDays[0], from: now, calendar: calendar)
        }
        return next
    }

    /// ローカル日付基準で「今日の復習」対象か（dueDate <= 今日）を判定する。
    static func isDue(
        _ state: WordReviewState,
        on date: Date = .now,
        calendar: Calendar = .current
    ) -> Bool {
        calendar.startOfDay(for: state.dueDate) <= calendar.startOfDay(for: date)
    }

    /// 深夜の解答でも日数がぶれないよう、当日0時を起点に加算する
    private static func dueDate(inDays days: Int, from now: Date, calendar: Calendar) -> Date {
        let today = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: days, to: today) ?? today
    }

    private static func clampedStep(_ index: Int) -> Int {
        min(max(index, 0), stepIntervalsInDays.count - 1)
    }
}
