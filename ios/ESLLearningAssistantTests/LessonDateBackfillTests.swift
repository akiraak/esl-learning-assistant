import SwiftData
import XCTest
@testable import ESLLearningAssistant

final class LessonDateBackfillTests: XCTestCase {
    private var calendar: Calendar { Calendar.current }

    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Class.self, Lesson.self, Photo.self, Word.self, WordOccurrence.self,
            configurations: config
        )
        return ModelContext(container)
    }

    private func day(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    /// 旧データ相当のレッスン（dateStorage 未設定）を作る
    private func makeLegacyLesson(in schoolClass: Class, title: String, createdAt: Date) -> Lesson {
        let lesson = Lesson(schoolClass: schoolClass, title: title, createdAt: createdAt)
        lesson.dateStorage = nil
        return lesson
    }

    // MARK: - Lesson.date / init

    func testInitSetsDateStorageToStartOfCreatedAtDay() throws {
        let context = try makeContext()
        let schoolClass = Class(name: "A")
        context.insert(schoolClass)
        let createdAt = day(2026, 7, 10, hour: 15)
        let lesson = Lesson(schoolClass: schoolClass, title: "Unit 1", createdAt: createdAt)
        context.insert(lesson)

        XCTAssertEqual(lesson.dateStorage, calendar.startOfDay(for: createdAt))
        XCTAssertEqual(lesson.date, calendar.startOfDay(for: createdAt))
    }

    func testInitWithExplicitDateNormalizesToStartOfDay() throws {
        let context = try makeContext()
        let schoolClass = Class(name: "A")
        context.insert(schoolClass)
        let lesson = Lesson(schoolClass: schoolClass, title: "Unit 1", date: day(2026, 8, 1, hour: 20))
        context.insert(lesson)

        XCTAssertEqual(lesson.date, day(2026, 8, 1))
    }

    func testDateFallsBackToCreatedAtDayWhenStorageIsNil() throws {
        let context = try makeContext()
        let schoolClass = Class(name: "A")
        context.insert(schoolClass)
        let lesson = makeLegacyLesson(in: schoolClass, title: "Unit 1", createdAt: day(2026, 7, 10, hour: 9))
        context.insert(lesson)

        XCTAssertNil(lesson.dateStorage)
        XCTAssertEqual(lesson.date, day(2026, 7, 10))
    }

    // MARK: - displayTitle

    func testDisplayTitleUsesTitleWhenPresent() throws {
        let context = try makeContext()
        let schoolClass = Class(name: "A")
        context.insert(schoolClass)
        let lesson = Lesson(schoolClass: schoolClass, title: "Unit 3 Reading")
        context.insert(lesson)

        XCTAssertEqual(lesson.displayTitle, "Unit 3 Reading")
    }

    func testDisplayTitleFallsBackToDateWhenTitleIsBlank() throws {
        let context = try makeContext()
        let schoolClass = Class(name: "A")
        context.insert(schoolClass)
        let lesson = Lesson(schoolClass: schoolClass, title: "  ", date: day(2026, 7, 10))
        context.insert(lesson)

        XCTAssertFalse(lesson.displayTitle.isEmpty)
        XCTAssertNotEqual(lesson.displayTitle, "  ")
        // 年・日を含む日付表示になっている（ロケール依存の書式そのものは固定しない）
        XCTAssertTrue(lesson.displayTitle.contains("2026"))
        XCTAssertTrue(lesson.displayTitle.contains("10"))
    }

    // MARK: - Class.lesson(on:)

    func testLessonOnDateMatchesSameDayOnly() throws {
        let context = try makeContext()
        let schoolClass = Class(name: "A")
        context.insert(schoolClass)
        let lesson = Lesson(schoolClass: schoolClass, title: "Unit 1", date: day(2026, 7, 10))
        context.insert(lesson)
        try context.save()

        // 同日なら時刻が違ってもヒットする
        XCTAssertEqual(schoolClass.lesson(on: day(2026, 7, 10, hour: 23))?.id, lesson.id)
        XCTAssertNil(schoolClass.lesson(on: day(2026, 7, 11)))
    }

    // MARK: - backfill

    func testBackfillAssignsCreatedAtDay() throws {
        let context = try makeContext()
        let schoolClass = Class(name: "A")
        context.insert(schoolClass)
        let l1 = makeLegacyLesson(in: schoolClass, title: "1", createdAt: day(2026, 7, 1, hour: 9))
        let l2 = makeLegacyLesson(in: schoolClass, title: "2", createdAt: day(2026, 7, 3, hour: 18))
        context.insert(l1)
        context.insert(l2)
        try context.save()

        LessonDateBackfill.backfill(lessons: schoolClass.lessons)

        XCTAssertEqual(l1.dateStorage, day(2026, 7, 1))
        XCTAssertEqual(l2.dateStorage, day(2026, 7, 3))
    }

    func testBackfillShiftsCollisionsToNextFreeDayInCreatedAtOrder() throws {
        let context = try makeContext()
        let schoolClass = Class(name: "A")
        context.insert(schoolClass)
        // 同日に3件 + その翌日に1件（順送り先がさらに埋まっているケース）
        let l1 = makeLegacyLesson(in: schoolClass, title: "1", createdAt: day(2026, 7, 1, hour: 9))
        let l2 = makeLegacyLesson(in: schoolClass, title: "2", createdAt: day(2026, 7, 1, hour: 12))
        let l3 = makeLegacyLesson(in: schoolClass, title: "3", createdAt: day(2026, 7, 1, hour: 15))
        let l4 = makeLegacyLesson(in: schoolClass, title: "4", createdAt: day(2026, 7, 2, hour: 9))
        for lesson in [l1, l2, l3, l4] { context.insert(lesson) }
        try context.save()

        LessonDateBackfill.backfill(lessons: schoolClass.lessons)

        // createdAt 昇順: l1 が 7/1、l2 は 7/2 へ…と順送り。l4（7/2 希望）は 7/2〜7/3 が
        // 埋まったため 7/4 へ
        XCTAssertEqual(l1.dateStorage, day(2026, 7, 1))
        XCTAssertEqual(l2.dateStorage, day(2026, 7, 2))
        XCTAssertEqual(l3.dateStorage, day(2026, 7, 3))
        XCTAssertEqual(l4.dateStorage, day(2026, 7, 4))
    }

    func testBackfillIsIdempotentAndKeepsExistingDates() throws {
        let context = try makeContext()
        let schoolClass = Class(name: "A")
        context.insert(schoolClass)
        // 日付設定済み（新形式）と未設定（旧形式）の混在
        let assigned = Lesson(schoolClass: schoolClass, title: "new", createdAt: day(2026, 7, 5, hour: 9), date: day(2026, 7, 20))
        let legacy = makeLegacyLesson(in: schoolClass, title: "old", createdAt: day(2026, 7, 5, hour: 10))
        context.insert(assigned)
        context.insert(legacy)
        try context.save()

        LessonDateBackfill.backfill(lessons: schoolClass.lessons)
        XCTAssertEqual(assigned.dateStorage, day(2026, 7, 20))
        XCTAssertEqual(legacy.dateStorage, day(2026, 7, 5))

        // 2回目は何も変わらない
        LessonDateBackfill.backfill(lessons: schoolClass.lessons)
        XCTAssertEqual(assigned.dateStorage, day(2026, 7, 20))
        XCTAssertEqual(legacy.dateStorage, day(2026, 7, 5))
    }
}
