import SwiftUI
import SwiftData

struct WordAddView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Class.createdAt) private var classes: [Class]
    @Query private var allWords: [Word]

    @State private var text = ""
    @State private var selectedLessonID: UUID?

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
                        .accessibilityIdentifier("wordTextField")
                } footer: {
                    Text("The translation, meanings, and examples will be generated automatically by AI.")
                }

                Section {
                    if let fixedLesson {
                        LabeledContent("Lesson") {
                            Text("\(fixedLesson.schoolClass.name) / \(fixedLesson.title)")
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
                        Text("This word will be linked to this lesson.")
                    } else {
                        Text("If you select a lesson, this word will be linked to it. You can also add it without a lesson.")
                    }
                }
            }
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
            }
        }
    }

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func addWord() {
        // 同一 text の既存 Word がある場合は新規作成せず、出現記録のみ追加する（data-model.md 6章）
        let word: Word
        if let existing = allWords.first(where: {
            $0.text.compare(trimmedText, options: [.caseInsensitive]) == .orderedSame
        }) {
            word = existing
        } else {
            // 訳語はAI生成の完了時に自動補完される（WordAIInfoGenerator）
            word = Word(text: trimmedText, translation: "")
            modelContext.insert(word)
        }

        if let lesson = fixedLesson {
            link(word, to: lesson)
        } else if let lessonID = selectedLessonID,
                  let lesson = classes.flatMap(\.lessons).first(where: { $0.id == lessonID }) {
            link(word, to: lesson)
        }
        // autosave任せだと直後にアプリを強制終了された場合に失われるため明示的に保存する
        try? modelContext.save()

        // AI単語情報を未生成なら生成開始（画面は閉じてバックグラウンドで継続）
        if word.aiInfoStatus == .none || word.aiInfoStatus == .failed {
            WordAIInfoGenerator.shared.generateInBackground(for: word)
        }
        dismiss()
    }

    /// 出現記録を作ってレッスンに紐付ける。to-one側（occurrence.lesson）の設定だけだと
    /// 逆側 lesson.wordOccurrences への反映と変更通知が次の保存まで遅れ、レッスン画面に
    /// 即時表示されないため、lesson側の配列にも明示的に追加する（関係の実体は同一）。
    private func link(_ word: Word, to lesson: Lesson) {
        let occurrence = WordOccurrence(word: word, lesson: lesson)
        modelContext.insert(occurrence)
        lesson.wordOccurrences.append(occurrence)
    }
}

#Preview {
    WordAddView()
        .modelContainer(for: [Class.self, Lesson.self, Photo.self, Word.self, WordOccurrence.self], inMemory: true)
}
