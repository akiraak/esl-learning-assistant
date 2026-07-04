import SwiftUI
import SwiftData

struct LessonMemoEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let lesson: Lesson

    @State private var memo = ""
    @FocusState private var isMemoFocused: Bool

    var body: some View {
        Form {
            Section {
                TextEditor(text: $memo)
                    .frame(minHeight: 240)
                    .focused($isMemoFocused)
                    .accessibilityIdentifier("lessonMemoEditor")
            } footer: {
                Text("Notes for this lesson (homework, teacher's comments, etc.)")
            }
        }
        .navigationTitle("Edit Memo")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: saveMemo)
            }
        }
        .onAppear {
            memo = lesson.memo ?? ""
            isMemoFocused = true
        }
    }

    private func saveMemo() {
        let trimmed = memo.trimmingCharacters(in: .whitespacesAndNewlines)
        // 空になったメモは nil に戻して「メモなし」扱いにする
        lesson.memo = trimmed.isEmpty ? nil : trimmed
        // autosave任せだと保存直後にアプリを終了された場合にメモが失われるため、明示的に保存する
        modelContext.saveOrLog()
        dismiss()
    }
}
