import Foundation
import SwiftData
import os

/// レッスンのカレンダー化（docs/plans/archive/lesson-calendar.md）に伴う既存データの授業日バックフィル（v1）。
///
/// `Lesson.dateStorage` はオプショナル追加のため既存行は NULL のままで、computed `date` は
/// createdAt の日付へフォールバックする。ただし「クラス内で同日レッスンは1つ」の一意制約を
/// 成立させるため、起動時に1回だけ全レッスンへ日付を明示保存する。同一クラス内で同日に
/// 複数レッスンがあった場合は createdAt 昇順で最初の1件がその日を取り、以降は翌日以降の
/// 空き日へ順送りする（データは消さない・決定的）。
enum LessonDateBackfill {
    /// 完了フラグ（UserDefaults）。端末ローカル処理のみなので保存成功で立てる。
    /// 失敗時は立てず、次回起動で再試行する（割り当ては冪等）
    static let completedDefaultsKey = "lessonDateBackfillV1"

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "ESLLearningAssistant",
        category: "LessonDateBackfill"
    )

    @MainActor
    static func runIfNeeded(modelContext: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: completedDefaultsKey) else { return }
        do {
            let classes = try modelContext.fetch(FetchDescriptor<Class>())
            for schoolClass in classes {
                backfill(lessons: schoolClass.lessons)
            }
            try modelContext.save()
            UserDefaults.standard.set(true, forKey: completedDefaultsKey)
            logger.log("lesson date backfill completed (\(classes.count, privacy: .public) classes)")
        } catch {
            logger.error("lesson date backfill failed: \(error, privacy: .public)")
        }
    }

    /// 1クラス分のレッスンへ授業日を割り当てる。createdAt 昇順で処理し、希望日
    /// （既に日付があればその日、なければ createdAt の日付）が埋まっていれば翌日以降の
    /// 空き日へ順送りする。全レッスンに日付が付いて衝突が無ければ何も変わらない（冪等）
    static func backfill(lessons: [Lesson]) {
        let calendar = Calendar.current
        var takenDays: [Date] = []
        for lesson in lessons.sorted(by: { $0.createdAt < $1.createdAt }) {
            var day = calendar.startOfDay(for: lesson.dateStorage ?? lesson.createdAt)
            while takenDays.contains(where: { calendar.isDate($0, inSameDayAs: day) }) {
                day = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
            }
            lesson.dateStorage = day
            takenDays.append(day)
        }
    }
}
