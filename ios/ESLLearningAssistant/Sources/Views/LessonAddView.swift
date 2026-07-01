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
                TextField("レッスン名（例: Unit 3 Reading）", text: $title)
                    .focused($isTitleFocused)
                    .accessibilityIdentifier("lessonTitleField")
            } footer: {
                Text("\(schoolClass.name) に追加します。")
            }
        }
        .navigationTitle("レッスンを追加")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("追加", action: addLesson)
                    .disabled(trimmedTitle.isEmpty)
            }
        }
        .onAppear { isTitleFocused = true }
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func addLesson() {
        let lesson = Lesson(schoolClass: schoolClass, title: trimmedTitle)
        modelContext.insert(lesson)
        currentClassID = schoolClass.id
        currentLessonID = lesson.id
        if let onCreated {
            onCreated()
        } else {
            dismiss()
        }
    }
}
