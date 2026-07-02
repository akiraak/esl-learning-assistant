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
                TextField("Class name (e.g. ESL Beginner A)", text: $name)
                    .focused($isNameFocused)
                    .accessibilityIdentifier("classNameField")
            } footer: {
                Text("A course or subject you are taking. You can add lessons after creating it.")
            }
        }
        .navigationTitle("Add Class")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Add", action: addClass)
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
