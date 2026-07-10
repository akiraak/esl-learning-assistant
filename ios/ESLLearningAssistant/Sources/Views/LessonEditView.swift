import SwiftUI
import SwiftData

/// レッスン名（任意ラベル）の編集。レッスンの識別子は授業日（クラス内で一意）なので、
/// 同名の重複チェックは行わず、空にすると表示は授業日（displayTitle）に戻る。
struct LessonEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let lesson: Lesson

    @State private var title = ""
    @FocusState private var isTitleFocused: Bool

    var body: some View {
        Form {
            Section {
                TextField("Lesson name (e.g. Unit 3 Reading)", text: $title)
                    .focused($isTitleFocused)
                    .accessibilityIdentifier("lessonTitleField")
            } footer: {
                Text("Optional. Leave empty to show the lesson date (\(lesson.date.formatted(date: .abbreviated, time: .omitted))).")
            }
        }
        .navigationTitle("Edit Lesson")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: saveLesson)
            }
        }
        .onAppear {
            title = lesson.title
            isTitleFocused = true
        }
    }

    private func saveLesson() {
        lesson.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        modelContext.saveOrLog()
        dismiss()
    }
}
