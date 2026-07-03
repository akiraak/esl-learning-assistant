import SwiftUI
import SwiftData

struct LessonAddView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let schoolClass: Class
    @Binding var currentClassID: UUID?
    @Binding var currentLessonID: UUID?
    /// 作成後の後処理（切り替えシートから開いた場合はシートごと閉じる）。未指定なら自身をポップする
    var onCreated: (() -> Void)?

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
                    Text("\(schoolClass.name) already has a lesson with this name.")
                        .foregroundStyle(.red)
                } else {
                    Text("Will be added to \(schoolClass.name).")
                }
            }
        }
        .navigationTitle("Add Lesson")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Add", action: addLesson)
                    .disabled(trimmedTitle.isEmpty || isDuplicateTitle)
            }
        }
        .onAppear { isTitleFocused = true }
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 同じクラス内に同名（大文字小文字を区別しない）のレッスンが既にあるか
    private var isDuplicateTitle: Bool {
        let candidate = trimmedTitle
        guard !candidate.isEmpty else { return false }
        return schoolClass.lessons.contains {
            $0.title.compare(candidate, options: [.caseInsensitive]) == .orderedSame
        }
    }

    private func addLesson() {
        guard !trimmedTitle.isEmpty, !isDuplicateTitle else { return }
        let lesson = Lesson(schoolClass: schoolClass, title: trimmedTitle)
        modelContext.insert(lesson)
        try? modelContext.save()
        currentClassID = schoolClass.id
        currentLessonID = lesson.id
        if let onCreated {
            onCreated()
        } else {
            dismiss()
        }
    }
}
