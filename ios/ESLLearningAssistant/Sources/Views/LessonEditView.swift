import SwiftUI
import SwiftData

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
                if isDuplicateTitle {
                    Text("\(lesson.schoolClass.name) already has a lesson with this name.")
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Edit Lesson")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: saveLesson)
                    .disabled(trimmedTitle.isEmpty || isDuplicateTitle)
            }
        }
        .onAppear {
            title = lesson.title
            isTitleFocused = true
        }
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 同じクラス内に同名（大文字小文字を区別しない）のレッスンが既にあるか（編集対象自身は除く）
    private var isDuplicateTitle: Bool {
        let candidate = trimmedTitle
        guard !candidate.isEmpty else { return false }
        return lesson.schoolClass.lessons.contains {
            $0.id != lesson.id
                && $0.title.compare(candidate, options: [.caseInsensitive]) == .orderedSame
        }
    }

    private func saveLesson() {
        guard !trimmedTitle.isEmpty, !isDuplicateTitle else { return }
        lesson.title = trimmedTitle
        modelContext.saveOrLog()
        dismiss()
    }
}
