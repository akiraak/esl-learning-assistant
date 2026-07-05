import SwiftUI
import SwiftData

/// 単語をレッスンに紐付ける／別レッスンへ付け替えるための選択シート。
/// `WordDetailView` の「Appears in Lessons」から追加・編集の両方で使う。
/// `excludedLessonIDs`（既にリンク済みのレッスン）は一覧から除外し、同一レッスンの
/// 行が二重に出ないようにする。選択すると `onSelect(lesson)` を呼んで dismiss する。
struct WordLessonPickerView: View {
    /// 一覧から除外するレッスン（既にこの単語がリンク済みのもの）
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
                                            Text(lesson.createdAt, style: .date)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        } label: {
                                            Text(lesson.title)
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
                        description: Text("This word is already linked to every lesson, or there are no lessons yet.")
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
            .sorted { $0.createdAt > $1.createdAt }
    }
}
