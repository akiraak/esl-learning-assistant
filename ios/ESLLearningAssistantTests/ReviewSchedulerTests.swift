import XCTest
@testable import ESLLearningAssistant

final class ReviewSchedulerTests: XCTestCase {
    // タイムゾーン依存の失敗を避けるため固定のカレンダーで検証する
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()

    private func date(
        _ year: Int, _ month: Int, _ day: Int,
        hour: Int = 12, minute: Int = 0
    ) -> Date {
        calendar.date(
            from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        )!
    }

    private func daysUntilDue(_ state: WordReviewState, from now: Date) -> Int {
        calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: now),
            to: calendar.startOfDay(for: state.dueDate)
        ).day!
    }

    func testCorrectAnswerAdvancesThroughAllSteps() {
        var state = WordReviewState(dueDate: date(2026, 7, 1))
        var now = date(2026, 7, 1)
        // 3日→7日→14日→30日→90日と進み、最終ステップは90日間隔を維持する
        let expected: [(interval: Int, stepIndex: Int)] = [
            (3, 1), (7, 2), (14, 3), (30, 4), (90, 4), (90, 4),
        ]
        for (index, expectation) in expected.enumerated() {
            state = ReviewScheduler.reviewed(state, isCorrect: true, at: now, calendar: calendar)
            XCTAssertEqual(daysUntilDue(state, from: now), expectation.interval, "\(index)回目の間隔")
            XCTAssertEqual(state.stepIndex, expectation.stepIndex, "\(index)回目のステップ")
            XCTAssertEqual(state.reviewCount, index + 1)
            XCTAssertEqual(state.correctCount, index + 1)
            XCTAssertEqual(state.lapseCount, 0)
            XCTAssertEqual(state.lastReviewedAt, now)
            now = state.dueDate
        }
    }

    func testIncorrectAnswerResetsToStepZero() {
        let now = date(2026, 7, 1)
        let state = WordReviewState(
            dueDate: now, reviewCount: 4, stepIndex: 3, correctCount: 4
        )
        let next = ReviewScheduler.reviewed(state, isCorrect: false, at: now, calendar: calendar)
        XCTAssertEqual(next.stepIndex, 0)
        XCTAssertEqual(daysUntilDue(next, from: now), 3)
        XCTAssertEqual(next.reviewCount, 5)
        XCTAssertEqual(next.correctCount, 4)
        XCTAssertEqual(next.lapseCount, 1)
    }

    func testLateNightReviewCountsFromLocalDay() {
        // 23:30の解答でも当日0時起点で日数を数える（深夜またぎで間隔がぶれない）
        let now = date(2026, 7, 1, hour: 23, minute: 30)
        let state = WordReviewState(dueDate: now)
        let next = ReviewScheduler.reviewed(state, isCorrect: true, at: now, calendar: calendar)
        XCTAssertEqual(daysUntilDue(next, from: now), 3)
        XCTAssertEqual(
            next.dueDate,
            calendar.startOfDay(for: date(2026, 7, 4))
        )
    }

    func testIsDueComparesLocalDates() {
        // 期日当日は時刻によらず対象、翌日が期日なら対象外
        let dueToday = WordReviewState(dueDate: date(2026, 7, 1, hour: 0, minute: 0))
        XCTAssertTrue(ReviewScheduler.isDue(
            dueToday, on: date(2026, 7, 1, hour: 23, minute: 59), calendar: calendar
        ))

        let dueTomorrow = WordReviewState(dueDate: date(2026, 7, 2, hour: 0, minute: 0))
        XCTAssertFalse(ReviewScheduler.isDue(
            dueTomorrow, on: date(2026, 7, 1, hour: 23, minute: 59), calendar: calendar
        ))

        // 期日超過（復習をサボった単語）も対象のまま
        let overdue = WordReviewState(dueDate: date(2026, 6, 1))
        XCTAssertTrue(ReviewScheduler.isDue(overdue, on: date(2026, 7, 1), calendar: calendar))
    }

    func testOutOfRangeStepIndexIsClamped() {
        // 将来ステップ数を減らした場合などの保存済み範囲外値も落ちずに最終ステップ扱いになる
        let now = date(2026, 7, 1)
        let state = WordReviewState(dueDate: now, stepIndex: 99)
        let next = ReviewScheduler.reviewed(state, isCorrect: true, at: now, calendar: calendar)
        XCTAssertEqual(daysUntilDue(next, from: now), 90)
        XCTAssertEqual(next.stepIndex, ReviewScheduler.stepIntervalsInDays.count - 1)
    }
}
