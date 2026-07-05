import SwiftUI
import SwiftData
import MarkdownUI

/// 作文の詳細・編集画面。英文と「伝えたかった意図（日本語）」をその場で編集でき、
/// 「Review」で AI 添削を取得する。添削は1回で終わらず、下書きを直して「Re-review」すると
/// 過去の全ラウンド（英文・修正・解説）を AI に渡し、文脈を踏まえて改善を続けられる。
/// 画面上部に履歴を古い順で並べ、下部の下書きエディタから次のラウンドを送る。
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

    /// 送信可能か: 英日とも非空、かつ下書きが最終ラウンドと相違（同一なら送る変更が無い）。
    private var canReview: Bool {
        guard !composition.englishText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !composition.japaneseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return false }
        return !composition.draftMatchesLastRound
    }

    var body: some View {
        List {
            // これまでの改善の履歴（古い順）。各ラウンド＝送った英文＋添削＋解説。
            ForEach(Array(composition.rounds.enumerated()), id: \.element.id) { index, round in
                roundSection(index: index, round: round)
            }

            Section {
                TextEditor(text: $composition.englishText)
                    .frame(minHeight: 120)
                    .focused($focusedField, equals: .english)
                    .accessibilityIdentifier("compositionEnglishEditor")
                    .onChange(of: composition.englishText) { touch() }
            } header: {
                TappableEnglishText(text: composition.hasFeedback ? "Revise Your English" : "Your English")
            } footer: {
                Text(composition.hasFeedback
                    ? "Edit your English based on the feedback above, then re-review to keep improving."
                    : "Write your composition in English.")
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
            if composition.previewText.isEmpty && !composition.hasFeedback {
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

    /// 「Review / Re-review」ボタンの行。生成中はスピナー、送る変更が無いときはヒントを出す。
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
                        composition.hasFeedback ? "Re-review" : "Review",
                        systemImage: "checkmark.circle"
                    )
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!canReview)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .accessibilityIdentifier("compositionReviewButton")
            }
        } footer: {
            reviewFooter
        }
    }

    /// 送信ボタン下のヒント。未入力／変更なしを出し分ける。
    @ViewBuilder
    private var reviewFooter: some View {
        let englishEmpty = composition.englishText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let japaneseEmpty = composition.japaneseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if englishEmpty || japaneseEmpty {
            Text("Enter both your English and what you meant to enable review.")
        } else if composition.draftMatchesLastRound {
            Text("Edit your English or note to review a new revision.")
        }
    }

    /// 1ラウンド分の履歴表示（送った英文＋修正英文＋解説）。修正英文は単語タップで単語帳登録に繋がる。
    @ViewBuilder
    private func roundSection(index: Int, round: WritingRound) -> some View {
        Section {
            labeledBlock(title: "You wrote") {
                TappableEnglishText(text: round.englishText)
                    .textSelection(.enabled)
            }
            labeledBlock(title: "Corrected") {
                TappableEnglishText(text: round.feedback.correctedText)
                    .textSelection(.enabled)
            }
            labeledBlock(title: "Explanation") {
                Markdown(round.feedback.explanation)
                    .textSelection(.enabled)
            }
        } header: {
            HStack {
                TappableEnglishText(text: "Round \(index + 1)")
                Spacer()
                Text(round.createdAt, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// 履歴内の小見出し付きブロック
    @ViewBuilder
    private func labeledBlock<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            TappableEnglishText(text: title, color: .secondary)
                .font(.caption)
                .foregroundStyle(.secondary)
            content()
        }
        .padding(.vertical, 2)
    }

    /// 本文編集のたびに updatedAt を進める（一覧の並び順・編集検知に使う）
    private func touch() {
        composition.updatedAt = .now
    }

    private func requestReview() {
        guard canReview, !isGenerating else { return }
        focusedField = nil
        let english = composition.englishText.trimmingCharacters(in: .whitespacesAndNewlines)
        let japanese = composition.japaneseText.trimmingCharacters(in: .whitespacesAndNewlines)
        // これまでの全ラウンドを history として渡し、文脈を踏まえた添削にする
        let history = composition.rounds.map { round in
            WritingFeedbackRoundPayload(
                englishText: round.englishText,
                japaneseText: round.japaneseText,
                correctedText: round.feedback.correctedText,
                explanation: round.feedback.explanation
            )
        }
        isGenerating = true
        Task { @MainActor in
            defer { isGenerating = false }
            do {
                let response = try await service.fetchFeedback(
                    englishText: english,
                    japaneseText: japanese,
                    explanationLanguage: composition.explanationLanguage,
                    history: history
                )
                let round = WritingRound(
                    englishText: english,
                    japaneseText: japanese,
                    feedback: WritingFeedback(
                        correctedText: response.feedback.correctedText,
                        explanation: response.feedback.explanation,
                        model: response.model,
                        generatedAt: .now
                    ),
                    createdAt: .now
                )
                composition.rounds = composition.rounds + [round]
                composition.updatedAt = .now
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
        englishText: "I went to school yesterday and I meet my friend.",
        japaneseText: "昨日学校に行って友達に会った。",
        explanationLanguage: "ja"
    )
    composition.rounds = [
        WritingRound(
            englishText: "I go to school yesterday and meet my friend.",
            japaneseText: "昨日学校に行って友達に会った。",
            feedback: WritingFeedback(
                correctedText: "I went to school yesterday and met my friend.",
                explanation: "- 「yesterday」があるため過去形にします。\n- go → went、meet → met に修正しました。",
                model: "claude-sonnet-5",
                generatedAt: .now
            ),
            createdAt: .now
        ),
        WritingRound(
            englishText: "I went to school yesterday and I meet my friend.",
            japaneseText: "昨日学校に行って友達に会った。",
            feedback: WritingFeedback(
                correctedText: "I went to school yesterday and met my friend.",
                explanation: "- 前回の go → went はばっちりです！\n- meet はまだ現在形なので met に直しましょう。",
                model: "claude-sonnet-5",
                generatedAt: .now
            ),
            createdAt: .now
        ),
    ]
    container.mainContext.insert(composition)
    return NavigationStack {
        CompositionDetailView(composition: composition)
    }
    .modelContainer(container)
}
