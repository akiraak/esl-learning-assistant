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

    func testCorrectAnswerAddsMasteryWithoutAdvancingDueDate() {
        let now = date(2026, 7, 1)
        var state = WordReviewState(dueDate: now)
        // 100% 未満の正解は習熟度だけ進み、dueDate・ステップは変わらない
        for expected in [20, 40, 60, 80] {
            state = ReviewScheduler.answered(state, isCorrect: true, at: now, calendar: calendar)
            XCTAssertEqual(state.masteryPercent, expected)
            XCTAssertEqual(state.stepIndex, 0)
            XCTAssertEqual(daysUntilDue(state, from: now), 0)
            XCTAssertEqual(state.lastReviewedAt, now)
        }
        XCTAssertEqual(state.reviewCount, 4)
        XCTAssertEqual(state.correctCount, 4)
        XCTAssertEqual(state.lapseCount, 0)
    }

    func testReachingFullMasteryClearsAndSchedulesNextStep() {
        let now = date(2026, 7, 1)
        let state = WordReviewState(dueDate: now, masteryPercent: 80)
        let next = ReviewScheduler.answered(state, isCorrect: true, at: now, calendar: calendar)
        // クリア: step 0 の間隔（1日）で次回日を設定し、ステップ前進・習熟度は次周回用に0へ
        XCTAssertEqual(daysUntilDue(next, from: now), 1)
        XCTAssertEqual(next.stepIndex, 1)
        XCTAssertEqual(next.masteryPercent, 0)
    }

    func testClearAdvancesThroughAllSteps() {
        var state = WordReviewState(dueDate: date(2026, 7, 1))
        var now = date(2026, 7, 1)
        // 各周回を5連続正解でクリアすると 1日→2日→3日→7日→14日→30日→90日 と進み、最終ステップは90日を維持
        let expected: [(interval: Int, stepIndex: Int)] = [
            (1, 1), (2, 2), (3, 3), (7, 4), (14, 5), (30, 6), (90, 6), (90, 6),
        ]
        for (index, expectation) in expected.enumerated() {
            for _ in 0..<5 {
                state = ReviewScheduler.answered(state, isCorrect: true, at: now, calendar: calendar)
            }
            XCTAssertEqual(daysUntilDue(state, from: now), expectation.interval, "\(index)周目の間隔")
            XCTAssertEqual(state.stepIndex, expectation.stepIndex, "\(index)周目のステップ")
            XCTAssertEqual(state.masteryPercent, 0)
            now = state.dueDate
        }
        XCTAssertEqual(state.reviewCount, 40)
        XCTAssertEqual(state.correctCount, 40)
    }

    func testIncorrectAnswerReducesMasteryAndResetsStepKeepingDueDate() {
        let now = date(2026, 7, 1)
        let state = WordReviewState(
            dueDate: now, reviewCount: 4, stepIndex: 3, correctCount: 4, masteryPercent: 50
        )
        let next = ReviewScheduler.answered(state, isCorrect: false, at: now, calendar: calendar)
        XCTAssertEqual(next.masteryPercent, 30)
        XCTAssertEqual(next.stepIndex, 0)
        // dueDate は変えない（クリアするまで出題対象に残る）
        XCTAssertEqual(next.dueDate, state.dueDate)
        XCTAssertEqual(next.reviewCount, 5)
        XCTAssertEqual(next.correctCount, 4)
        XCTAssertEqual(next.lapseCount, 1)
    }

    func testMasteryIsClampedToBounds() {
        let now = date(2026, 7, 1)
        // 下限0: 0% で不正解しても負にならない
        let zero = WordReviewState(dueDate: now, masteryPercent: 0)
        XCTAssertEqual(
            ReviewScheduler.answered(zero, isCorrect: false, at: now, calendar: calendar).masteryPercent,
            0
        )
        // 20刻み以外の保存値（将来の増減幅変更など）でも100を超えず、クリアとして処理される
        let almost = WordReviewState(dueDate: now, masteryPercent: 90)
        let cleared = ReviewScheduler.answered(almost, isCorrect: true, at: now, calendar: calendar)
        XCTAssertEqual(cleared.masteryPercent, 0)
        XCTAssertEqual(daysUntilDue(cleared, from: now), 1)
    }

    func testLateNightClearCountsFromLocalDay() {
        // 23:30の解答でも当日0時起点で日数を数える（深夜またぎで間隔がぶれない）
        let now = date(2026, 7, 1, hour: 23, minute: 30)
        let state = WordReviewState(dueDate: now, masteryPercent: 80)
        let next = ReviewScheduler.answered(state, isCorrect: true, at: now, calendar: calendar)
        XCTAssertEqual(daysUntilDue(next, from: now), 1)
        XCTAssertEqual(
            next.dueDate,
            calendar.startOfDay(for: date(2026, 7, 2))
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
        let state = WordReviewState(dueDate: now, stepIndex: 99, masteryPercent: 80)
        let next = ReviewScheduler.answered(state, isCorrect: true, at: now, calendar: calendar)
        XCTAssertEqual(daysUntilDue(next, from: now), 90)
        XCTAssertEqual(next.stepIndex, ReviewScheduler.stepIntervalsInDays.count - 1)
    }
}
