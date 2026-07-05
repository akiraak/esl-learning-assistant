import SwiftUI
import SwiftData
import MarkdownUI

/// 作文の詳細・編集画面。英文と「伝えたかった意図（日本語）」をその場で編集でき、
/// 「Review」で AI 添削を取得して結果を表示する。本文を編集すると既存の添削は「古い」扱いになり、
/// 再添削を促す。送信前は何度でも編集できる（都度 updatedAt を更新）。
struct CompositionDetailView: View {
    @Bindable var composition: Composition
    /// 一覧の「＋」から作られた直後か（英文欄を自動フォーカスする）
    var isNew: Bool = false

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var isConfirmingDelete = false
    @FocusState private var focusedField: Field?

    private let service = RemoteWritingFeedbackService()

    private enum Field { case english, japanese }

    private var canReview: Bool {
        !composition.englishText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !composition.japaneseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        List {
            Section {
                TextEditor(text: $composition.englishText)
                    .frame(minHeight: 120)
                    .focused($focusedField, equals: .english)
                    .accessibilityIdentifier("compositionEnglishEditor")
                    .onChange(of: composition.englishText) { touch() }
            } header: {
                TappableEnglishText(text: "Your English")
            } footer: {
                Text("Write your composition in English.")
            }

            Section {
                TextEditor(text: $composition.japaneseText)
                    .frame(minHeight: 80)
                    .focused($focusedField, equals: .japanese)
                    .accessibilityIdentifier("compositionJapaneseEditor")
                    .onChange(of: composition.japaneseText) { touch() }
            } header: {
                TappableEnglishText(text: "What You Meant")
            } footer: {
                Text("The meaning you wanted to express (a translation or note in your language). This helps the AI correct toward your intent.")
            }

            reviewSection

            if let feedback = composition.feedback {
                feedbackSections(feedback)
            }

            Section {
                Button(role: .destructive) {
                    isConfirmingDelete = true
                } label: {
                    Label("Delete Composition", systemImage: "trash")
                        .foregroundStyle(.red)
                }
                .accessibilityIdentifier("compositionDeleteButton")
            }
        }
        .navigationTitle("Composition")
        .navigationBarTitleDisplayMode(.inline)
        .wordTapRegistration()
        .onAppear {
            if isNew && composition.previewText.isEmpty {
                focusedField = .english
            }
        }
        // 空のまま離脱した新規作文（本文も添削も無い）は残さず掃除する
        .onDisappear {
            modelContext.saveOrLog()
            if composition.previewText.isEmpty && composition.feedback == nil {
                modelContext.delete(composition)
                modelContext.saveOrLog()
            }
        }
        .alert(
            "Review Failed",
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .confirmationDialog(
            "Delete this composition?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { deleteComposition() }
        } message: {
            Text("The composition and its feedback will be removed.")
        }
    }

    /// 「Review / Re-review」ボタンの行。生成中はスピナー、本文編集後は再添削を促す注記を出す。
    private var reviewSection: some View {
        Section {
            if isGenerating {
                HStack(spacing: 12) {
                    ProgressView()
                    TappableEnglishText(text: "Reviewing…", color: .secondary)
                        .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("compositionReviewingLabel")
            } else {
                Button {
                    requestReview()
                } label: {
                    Label(
                        composition.feedback == nil ? "Review" : "Re-review",
                        systemImage: "checkmark.circle"
                    )
                }
                .disabled(!canReview)
                .accessibilityIdentifier("compositionReviewButton")
            }

            if composition.isFeedbackStale {
                Label("You edited the text after the last review. Re-review to update the feedback.", systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        } footer: {
            if !canReview {
                Text("Enter both your English and what you meant to enable review.")
            }
        }
    }

    /// 添削結果の表示（修正英文＋解説）。修正英文は単語タップで単語帳登録に繋がる。
    @ViewBuilder
    private func feedbackSections(_ feedback: WritingFeedback) -> some View {
        Section {
            TappableEnglishText(text: feedback.correctedText)
                .textSelection(.enabled)
        } header: {
            TappableEnglishText(text: "Corrected")
        }

        Section {
            Markdown(feedback.explanation)
                .textSelection(.enabled)
        } header: {
            TappableEnglishText(text: "Explanation")
        }

        Section {
            LabeledContent {
                Text(feedback.generatedAt, style: .date)
            } label: {
                TappableEnglishText(text: "Reviewed")
            }
            LabeledContent {
                Text(feedback.model)
            } label: {
                TappableEnglishText(text: "Model")
            }
        }
    }

    /// 本文編集のたびに updatedAt を進める（添削の新旧判定に使う）
    private func touch() {
        composition.updatedAt = .now
    }

    private func requestReview() {
        guard canReview, !isGenerating else { return }
        focusedField = nil
        let english = composition.englishText.trimmingCharacters(in: .whitespacesAndNewlines)
        let japanese = composition.japaneseText.trimmingCharacters(in: .whitespacesAndNewlines)
        isGenerating = true
        Task { @MainActor in
            defer { isGenerating = false }
            do {
                let response = try await service.fetchFeedback(
                    englishText: english,
                    japaneseText: japanese,
                    explanationLanguage: composition.explanationLanguage
                )
                composition.feedback = WritingFeedback(
                    correctedText: response.feedback.correctedText,
                    explanation: response.feedback.explanation,
                    model: response.model,
                    generatedAt: .now
                )
                modelContext.saveOrLog()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func deleteComposition() {
        dismiss()
        modelContext.delete(composition)
        modelContext.saveOrLog()
    }
}

#Preview {
    let container = try! ModelContainer(
        for: Class.self, Lesson.self, Photo.self, Word.self, WordOccurrence.self, Composition.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let composition = Composition(
        englishText: "I go to school yesterday and meet my friend.",
        japaneseText: "昨日学校に行って友達に会った。",
        explanationLanguage: "ja"
    )
    composition.feedback = WritingFeedback(
        correctedText: "I went to school yesterday and met my friend.",
        explanation: "- 「yesterday」があるため過去形にします。\n- go → went、meet → met に修正しました。",
        model: "claude-sonnet-5",
        generatedAt: .now
    )
    container.mainContext.insert(composition)
    return NavigationStack {
        CompositionDetailView(composition: composition)
    }
    .modelContainer(container)
}
