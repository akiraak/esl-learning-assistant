import Foundation

/// 単語復習の間隔反復スケジューラ（固定ステップの Leitner 方式）。
/// docs/specs/data-model.md §5 / docs/plans/archive/word-memorization-quiz.md §3.1。
/// SM-2 / FSRS への将来差し替えを想定し、モデルから分離した純関数として実装する。
enum ReviewScheduler {
    /// 復習ステップの間隔（日）。最終ステップ到達後は90日間隔を維持する。
    static let stepIntervalsInDays = [3, 7, 14, 30, 90]

    /// 1問の解答での習熟度の増減幅（%）
    static let masteryDeltaPercent = 25
    /// この習熟度に到達するとクリア（次回復習日へ前進）
    static let masteryClearPercent = 100

    /// 1回の解答結果を反映した新しい復習状態を返す（習熟度方式）。
    /// - 正解: 習熟度 +25%（上限100）。100% でクリアとなり、現在ステップの間隔で次回日を
    ///   設定してステップを1つ進め（最終ステップでは維持）、習熟度を次周回用に 0 へ戻す
    /// - 不正解: 習熟度 −25%（下限0）、ステップを0に戻す。dueDate は変えない
    ///   （クリアするまで出題対象に残り続ける）
    static func answered(
        _ state: WordReviewState,
        isCorrect: Bool,
        at now: Date = .now,
        calendar: Calendar = .current
    ) -> WordReviewState {
        var next = state
        next.lastReviewedAt = now
        next.reviewCount += 1
        if isCorrect {
            next.correctCount += 1
            next.masteryPercent = min(state.masteryPercent + masteryDeltaPercent, masteryClearPercent)
            if next.masteryPercent >= masteryClearPercent {
                let step = clampedStep(state.stepIndex)
                next.stepIndex = min(step + 1, stepIntervalsInDays.count - 1)
                next.dueDate = dueDate(inDays: stepIntervalsInDays[step], from: now, calendar: calendar)
                next.masteryPercent = 0
            }
        } else {
            next.lapseCount += 1
            next.stepIndex = 0
            next.masteryPercent = max(state.masteryPercent - masteryDeltaPercent, 0)
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
