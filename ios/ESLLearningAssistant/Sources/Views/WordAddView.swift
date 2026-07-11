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

    /// Add 押下後の正規化（原形化・綴り訂正）の非同期待ち。true の間は Add をスピナーに差し替える。
    @State private var isNormalizing = false
    /// 訂正候補が出たときの確認ダイアログ用。nil でダイアログ非表示。
    @State private var pendingConfirmation: WordNormalization?

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
                    TextField("Word or phrase (e.g. apple, look up)", text: $text)
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
                            Text("\(fixedLesson.schoolClass.name) / \(fixedLesson.displayTitle)")
                        } label: {
                            TappableEnglishText(text: "Lesson")
                        }
                        .accessibilityIdentifier("wordLessonFixedLabel")
                    } else {
                        Picker("Lesson", selection: $selectedLessonID) {
                            Text("None").tag(UUID?.none)
                            ForEach(classes) { schoolClass in
                                ForEach(schoolClass.lessons.sorted { $0.date > $1.date }) { lesson in
                                    Text("\(schoolClass.name) / \(lesson.displayTitle)")
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
                    // 正規化の非同期待ちの間はスピナー表示（二重押下防止も兼ねる）
                    if isNormalizing {
                        ProgressView()
                            .accessibilityIdentifier("wordNormalizeProgress")
                    } else {
                        Button("Add", action: addWord)
                            .disabled(normalizedText.isEmpty || duplicateMessage != nil)
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isNormalizing)
                }
                // ナビタイトル "Add Word" は principal 化しない: 単語 "Add" がツールバーの
                // Add ボタンと a11y クエリ（navigationBars.buttons["Add"]）で衝突し、UIテストを壊すため
            }
            .onAppear { isTextFocused = true }
            // 訂正候補（原形/正しい綴り）の確認。主=正規化形 / 逃げ道=入力形 / Cancel。
            // UI 文言は他画面と揃えて英語、説明（reason）のみ母語（バックエンド生成）。
            .confirmationDialog(
                "Register the suggested form?",
                isPresented: isConfirmationPresented,
                titleVisibility: .visible,
                presenting: pendingConfirmation
            ) { normalization in
                Button("Register “\(normalization.effectiveLemma)”") {
                    register(text: normalization.effectiveLemma)
                    dismiss()
                }
                Button("Keep “\(normalization.input)”") {
                    register(text: normalization.input)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: { normalization in
                Text(normalization.reason)
            }
        }
    }

    /// 入力の空白正規化（trim + 連続空白→単一スペース）。重複判定・正規化・登録の全てで
    /// この形を使い、"look  up" が "look up" と別語扱いにならないようにする（WordRegistrar と同一規則）。
    private var normalizedText: String {
        WordRegistrar.normalizeSpacing(text)
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
        guard !normalizedText.isEmpty else { return nil }
        guard let existing = allWords.first(where: {
            $0.text.compare(normalizedText, options: [.caseInsensitive]) == .orderedSame
        }) else { return nil }

        if let lesson = effectiveLesson {
            let alreadyInLesson = existing.occurrences.contains { $0.lesson.id == lesson.id }
            return alreadyInLesson ? "“\(existing.text)” is already in this lesson." : nil
        }
        return "“\(existing.text)” is already in your word list."
    }

    /// 確認ダイアログの表示状態を pendingConfirmation に橋渡しする。
    private var isConfirmationPresented: Binding<Bool> {
        Binding(
            get: { pendingConfirmation != nil },
            set: { if !$0 { pendingConfirmation = nil } }
        )
    }

    private func addWord() {
        // 重複時は Add ボタンが無効なので通常ここには来ないが、防御的にガードする。
        guard duplicateMessage == nil else { return }
        let input = normalizedText
        guard !input.isEmpty else { return }

        // Add 押下 → 正規化（原形化・綴り訂正）→ 訂正候補があれば確認ダイアログ、無ければ即登録。
        // 正規化失敗（オフライン等）は登録をブロックせず入力のまま登録へフォールバックする。
        isNormalizing = true
        let service = RemoteWordNormalizeService()
        Task {
            let decision = await WordNormalizationFlow.decide(
                input: input,
                targetLanguage: WordNormalizationFlow.targetLanguage,
                using: service
            )
            isNormalizing = false
            switch decision {
            case .registerImmediately(let text):
                register(text: text)
                dismiss()
            case .confirm(let normalization):
                pendingConfirmation = normalization
            }
        }
    }

    /// 同綴りの既存Word再利用・新規作成・レッスン紐付け・保存・AI生成トリガは WordRegistrar に集約
    /// （英文タップ登録と共通。data-model.md 6章）。正規化形が既存語なら再利用されて集約される。
    private func register(text: String) {
        WordRegistrar.register(
            text: text,
            in: modelContext,
            existingWords: allWords,
            lesson: effectiveLesson
        )
    }
}

#Preview {
    WordAddView()
        .modelContainer(for: [Class.self, Lesson.self, Photo.self, Word.self, WordOccurrence.self, Composition.self, AudioClip.self, YouTubeLink.self, Document.self], inMemory: true)
}
