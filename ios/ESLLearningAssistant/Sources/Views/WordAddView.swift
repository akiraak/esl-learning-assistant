import SwiftUI
import SwiftData

struct WordAddView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Class.createdAt) private var classes: [Class]
    @Query private var allWords: [Word]

    @State private var text = ""
    @State private var translation = ""
    @State private var exampleSentence = ""
    @State private var partOfSpeech = ""
    @State private var selectedLessonID: UUID?

    var body: some View {
        NavigationStack {
            Form {
                Section("単語") {
                    TextField("見出し語（例: apple）", text: $text)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("訳語（例: りんご）", text: $translation)
                }

                Section("任意") {
                    TextField("例文", text: $exampleSentence, axis: .vertical)
                    TextField("品詞（例: 名詞）", text: $partOfSpeech)
                }

                Section {
                    Picker("レッスン", selection: $selectedLessonID) {
                        Text("なし").tag(UUID?.none)
                        ForEach(classes) { schoolClass in
                            ForEach(schoolClass.lessons.sorted { $0.createdAt > $1.createdAt }) { lesson in
                                Text("\(schoolClass.name) / \(lesson.title)")
                                    .tag(Optional(lesson.id))
                            }
                        }
                    }
                    .accessibilityIdentifier("wordLessonPicker")
                } footer: {
                    Text("レッスンを指定すると、この単語がそのレッスンに関連付きます。指定なしでも登録できます。")
                }
            }
            .navigationTitle("単語を追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("追加", action: addWord)
                        .disabled(trimmedText.isEmpty || trimmedTranslation.isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
            }
        }
    }

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedTranslation: String {
        translation.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func addWord() {
        // 同一 text の既存 Word がある場合は新規作成せず、出現記録のみ追加する（data-model.md 6章）
        let word: Word
        if let existing = allWords.first(where: {
            $0.text.compare(trimmedText, options: [.caseInsensitive]) == .orderedSame
        }) {
            word = existing
        } else {
            let trimmedExample = exampleSentence.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedPartOfSpeech = partOfSpeech.trimmingCharacters(in: .whitespacesAndNewlines)
            word = Word(
                text: trimmedText,
                translation: trimmedTranslation,
                exampleSentence: trimmedExample.isEmpty ? nil : trimmedExample,
                partOfSpeech: trimmedPartOfSpeech.isEmpty ? nil : trimmedPartOfSpeech
            )
            modelContext.insert(word)
        }

        if let lessonID = selectedLessonID,
           let lesson = classes.flatMap(\.lessons).first(where: { $0.id == lessonID }) {
            modelContext.insert(WordOccurrence(word: word, lesson: lesson))
        }
        dismiss()
    }
}

#Preview {
    WordAddView()
        .modelContainer(for: [Class.self, Lesson.self, Photo.self, Word.self, WordOccurrence.self], inMemory: true)
}
