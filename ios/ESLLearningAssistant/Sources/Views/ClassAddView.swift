import SwiftUI
import SwiftData

struct ClassAddView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Binding var currentClassID: UUID?
    @Binding var currentLessonID: UUID?

    @State private var name = ""
    @FocusState private var isNameFocused: Bool

    var body: some View {
        Form {
            Section {
                TextField("クラス名（例: ESL Beginner A）", text: $name)
                    .focused($isNameFocused)
                    .accessibilityIdentifier("classNameField")
            } footer: {
                Text("受講しているコース・科目の単位です。作成後にレッスンを追加できます。")
            }
        }
        .navigationTitle("クラスを追加")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("追加", action: addClass)
                    .disabled(trimmedName.isEmpty)
            }
        }
        .onAppear { isNameFocused = true }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func addClass() {
        let newClass = Class(name: trimmedName)
        modelContext.insert(newClass)
        currentClassID = newClass.id
        currentLessonID = nil
        dismiss()
    }
}

#Preview {
    NavigationStack {
        ClassAddView(currentClassID: .constant(nil), currentLessonID: .constant(nil))
    }
    .modelContainer(for: [Class.self, Lesson.self, Photo.self, Word.self, WordOccurrence.self], inMemory: true)
}
