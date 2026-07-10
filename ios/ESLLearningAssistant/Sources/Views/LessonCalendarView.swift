import SwiftUI
import UIKit

/// クラスのレッスンカレンダー（UICalendarView のラッパー）。
/// レッスンのある日にドット、現在レッスンの日にチェックのデコレーションを表示し、
/// 日付タップを `onSelectDate` で通知する。タップはコマンドとして扱い、選択リングは
/// 残さない（その日のレッスン有無による選択/作成の分岐は呼び出し側で行う）。
struct LessonCalendarView: UIViewRepresentable {
    let schoolClass: Class
    let currentLessonID: UUID?
    let onSelectDate: (Date) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UICalendarView {
        let view = UICalendarView()
        view.calendar = Calendar.current
        view.delegate = context.coordinator
        view.selectionBehavior = UICalendarSelectionSingleDate(delegate: context.coordinator)
        // 現在レッスンの月から表示を始める（該当なしなら今月）
        if let lesson = schoolClass.lessons.first(where: { $0.id == currentLessonID }) {
            view.visibleDateComponents = Calendar.current.dateComponents([.year, .month], from: lesson.date)
        }
        return view
    }

    func updateUIView(_ uiView: UICalendarView, context: Context) {
        context.coordinator.parent = self
        // レッスンの増減・クラス切り替え・現在レッスンの変更でデコレーションを引き直す。
        // 消えた日も消すため、前回分と今回分の和集合をリロードする
        let days = Set(schoolClass.lessons.map { Self.dayComponents(of: $0.date) })
        let stale = context.coordinator.decoratedDays
        context.coordinator.decoratedDays = days
        let toReload = Array(days.union(stale))
        if !toReload.isEmpty {
            uiView.reloadDecorations(forDateComponents: toReload, animated: false)
        }
    }

    static func dayComponents(of date: Date) -> DateComponents {
        Calendar.current.dateComponents([.year, .month, .day], from: date)
    }

    final class Coordinator: NSObject, UICalendarViewDelegate, UICalendarSelectionSingleDateDelegate {
        var parent: LessonCalendarView
        var decoratedDays: Set<DateComponents> = []

        init(_ parent: LessonCalendarView) {
            self.parent = parent
        }

        func calendarView(
            _ calendarView: UICalendarView,
            decorationFor dateComponents: DateComponents
        ) -> UICalendarView.Decoration? {
            guard let date = Calendar.current.date(from: dateComponents),
                  let lesson = parent.schoolClass.lesson(on: date) else { return nil }
            if lesson.id == parent.currentLessonID {
                return .image(UIImage(systemName: "checkmark.circle.fill"), color: .tintColor, size: .large)
            }
            return .default(color: .tintColor, size: .large)
        }

        func dateSelection(
            _ selection: UICalendarSelectionSingleDate,
            didSelectDate dateComponents: DateComponents?
        ) {
            guard let dateComponents, let date = Calendar.current.date(from: dateComponents) else { return }
            selection.setSelected(nil, animated: false)
            parent.onSelectDate(date)
        }

        func dateSelection(
            _ selection: UICalendarSelectionSingleDate,
            canSelectDate dateComponents: DateComponents?
        ) -> Bool {
            dateComponents != nil
        }
    }
}
