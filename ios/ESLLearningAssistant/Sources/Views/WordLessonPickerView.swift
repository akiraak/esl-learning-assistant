import SwiftUI
import SwiftData

/// レッスンをクラスごとにグルーピングして 1つ選ばせる汎用の選択シート。
/// 単語（`WordDetailView` の「Appears in Lessons」）と音声（`AudioDetailView` の「Lessons」）の
/// 追加・付け替えで共用する。`excludedLessonIDs`（既にリンク済みのレッスン）は一覧から除外し、
/// 同一レッスンの行が二重に出ないようにする。選択すると `onSelect(lesson)` を呼んで dismiss する。
struct WordLessonPickerView: View {
    /// 一覧から除外するレッスン（既にリンク済みのもの）
    let excludedLessonIDs: Set<UUID>
    let title: String
    let onSelect: (Lesson) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Class.createdAt) private var classes: [Class]

    var body: some View {
        NavigationStack {
            List {
                let hasAny = classes.contains { !selectableLessons(in: $0).isEmpty }
                if hasAny {
                    ForEach(classes) { schoolClass in
                        let lessons = selectableLessons(in: schoolClass)
                        if !lessons.isEmpty {
                            Section(schoolClass.name) {
                                ForEach(lessons) { lesson in
                                    Button {
                                        onSelect(lesson)
                                        dismiss()
                                    } label: {
                                        LabeledContent {
                                            Text(lesson.date, style: .date)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        } label: {
                                            Text(lesson.displayTitle)
                                                .foregroundStyle(.primary)
                                        }
                                    }
                                    .accessibilityIdentifier("wordLessonPickerRow")
                                }
                            }
                        }
                    }
                } else {
                    ContentUnavailableView(
                        "No Available Lessons",
                        systemImage: "book.closed",
                        description: Text("It is already linked to every lesson, or there are no lessons yet.")
                    )
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    /// クラス内の選択可能レッスン（除外分を除き新しい順）
    private func selectableLessons(in schoolClass: Class) -> [Lesson] {
        schoolClass.lessons
            .filter { !excludedLessonIDs.contains($0.id) }
            .sorted { $0.date > $1.date }
    }
}
