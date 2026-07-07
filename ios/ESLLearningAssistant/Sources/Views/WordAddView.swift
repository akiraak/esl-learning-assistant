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
                    if let duplicateMessage {
                        // 既存単語はアプリ側で弾く（Add 無効化）。説明文で理由を伝える。
                        Label(duplicateMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .accessibilityIdentifier("wordDuplicateWarning")
                    } else {
                        TappableEnglishText(text: "The translation, meanings, and examples will be generated automatically by AI.")
                    }
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
                        .disabled(trimmedText.isEmpty || duplicateMessage != nil)
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

    /// 実際に紐付けられるレッスン（固定レッスン優先、無ければ Picker 選択）。
    private var effectiveLesson: Lesson? {
        fixedLesson
            ?? selectedLessonID.flatMap { id in classes.flatMap(\.lessons).first { $0.id == id } }
    }

    /// 入力語が「純粋な重複」なら弾く理由メッセージを返す（Add を無効化）。nil なら追加可能。
    /// - レッスン未指定で同綴り既存語あり → 一覧の重複。
    /// - レッスン指定ありでその単語が既にそのレッスンに出現 → レッスン内の重複。
    /// - レッスン指定ありでまだ未紐付けなら「新規リンク」が生じる有用な操作なので弾かない（nil）。
    private var duplicateMessage: String? {
        guard !trimmedText.isEmpty else { return nil }
        guard let existing = allWords.first(where: {
            $0.text.compare(trimmedText, options: [.caseInsensitive]) == .orderedSame
        }) else { return nil }

        if let lesson = effectiveLesson {
            let alreadyInLesson = existing.occurrences.contains { $0.lesson.id == lesson.id }
            return alreadyInLesson ? "“\(existing.text)” is already in this lesson." : nil
        }
        return "“\(existing.text)” is already in your word list."
    }

    private func addWord() {
        // 重複時は Add ボタンが無効なので通常ここには来ないが、防御的にガードする。
        guard duplicateMessage == nil else { return }
        // 同綴りの既存Word再利用・新規作成・レッスン紐付け・保存・AI生成トリガは WordRegistrar に集約
        // （英文タップ登録と共通。data-model.md 6章）
        WordRegistrar.register(
            text: trimmedText,
            in: modelContext,
            existingWords: allWords,
            lesson: effectiveLesson
        )
        dismiss()
    }
}

#Preview {
    WordAddView()
        .modelContainer(for: [Class.self, Lesson.self, Photo.self, Word.self, WordOccurrence.self, Composition.self, AudioClip.self, YouTubeLink.self], inMemory: true)
}
