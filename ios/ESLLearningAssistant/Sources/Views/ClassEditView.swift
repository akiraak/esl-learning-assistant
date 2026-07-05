import SwiftUI
import SwiftData

struct ClassEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let schoolClass: Class

    @State private var name = ""
    @FocusState private var isNameFocused: Bool

    var body: some View {
        Form {
            Section {
                TextField("Class name (e.g. ESL Beginner A)", text: $name)
                    .focused($isNameFocused)
                    .accessibilityIdentifier("classNameField")
            }
        }
        .navigationTitle("Edit Class")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: saveClass)
                    .disabled(trimmedName.isEmpty)
            }
        }
        .onAppear {
            name = schoolClass.name
            isNameFocused = true
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func saveClass() {
        guard !trimmedName.isEmpty else { return }
        schoolClass.name = trimmedName
        modelContext.saveOrLog()
        dismiss()
    }
}

#Preview {
    NavigationStack {
        ClassEditView(schoolClass: Class(name: "ESL Beginner A"))
    }
    .modelContainer(for: [Class.self, Lesson.self, Photo.self, Word.self, WordOccurrence.self, Composition.self], inMemory: true)
}
