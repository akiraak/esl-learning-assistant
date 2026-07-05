import SwiftUI
import SwiftData

struct WordAddView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Class.createdAt) private var classes: [Class]
    @Query private var allWords: [Word]

    @State private var text = ""
    @State private var selectedLessonID: UUID?
    @FocusState private var isTextFocused: Bool

    /// レッスンを固定して開く場合に指定する。指定時はレッスンを変更できない。
    private let fixedLesson: Lesson?

    init(fixedLesson: Lesson? = nil) {
        self.fixedLesson = fixedLesson
        _selectedLessonID = State(initialValue: fixedLesson?.id)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Word (e.g. apple)", text: $text)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($isTextFocused)
                        .accessibilityIdentifier("wordTextField")
                } footer: {
                    TappableEnglishText(text: "The translation, meanings, and examples will be generated automatically by AI.")
                }

                Section {
                    if let fixedLesson {
                        LabeledContent {
                            Text("\(fixedLesson.schoolClass.name) / \(fixedLesson.title)")
                        } label: {
                            TappableEnglishText(text: "Lesson")
                        }
                        .accessibilityIdentifier("wordLessonFixedLabel")
                    } else {
                        Picker("Lesson", selection: $selectedLessonID) {
                            Text("None").tag(UUID?.none)
                            ForEach(classes) { schoolClass in
                                ForEach(schoolClass.lessons.sorted { $0.createdAt > $1.createdAt }) { lesson in
                                    Text("\(schoolClass.name) / \(lesson.title)")
                                        .tag(Optional(lesson.id))
                                }
                            }
                        }
                        .accessibilityIdentifier("wordLessonPicker")
                    }
                } footer: {
                    if fixedLesson != nil {
                        TappableEnglishText(text: "This word will be linked to this lesson.")
                    } else {
                        TappableEnglishText(text: "If you select a lesson, this word will be linked to it. You can also add it without a lesson.")
                    }
                }
            }
            .wordTapRegistration()
            .navigationTitle("Add Word")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", action: addWord)
                        .disabled(trimmedText.isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                // ナビタイトル "Add Word" は principal 化しない: 単語 "Add" がツールバーの
                // Add ボタンと a11y クエリ（navigationBars.buttons["Add"]）で衝突し、UIテストを壊すため
            }
            .onAppear { isTextFocused = true }
        }
    }

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func addWord() {
        // 同綴りの既存Word再利用・新規作成・レッスン紐付け・保存・AI生成トリガは WordRegistrar に集約
        // （英文タップ登録と共通。data-model.md 6章）
        let lesson = fixedLesson
            ?? selectedLessonID.flatMap { id in classes.flatMap(\.lessons).first { $0.id == id } }
        WordRegistrar.register(
            text: trimmedText,
            in: modelContext,
            existingWords: allWords,
            lesson: lesson
        )
        dismiss()
    }
}

#Preview {
    WordAddView()
        .modelContainer(for: [Class.self, Lesson.self, Photo.self, Word.self, WordOccurrence.self, Composition.self], inMemory: true)
}
