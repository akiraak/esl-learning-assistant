import SwiftUI
import SwiftData

struct WordDetailView: View {
    let word: Word

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    // 訂正時の衝突（正規化形が既存語と一致）判定に全単語を参照する
    @Query private var allWords: [Word]

    @State private var isConfirmingRegenerate = false
    @State private var isConfirmingDelete = false
    @State private var lessonPickerMode: LessonPickerMode?
    @StateObject private var speechService = SpeechService()
    @State private var speakingText: String?
    @StateObject private var ttsPlayback = TTSPlaybackService()
    @State private var ttsErrorMessage: String?

    /// 「Correct Word」押下後の正規化（原形化・綴り訂正）の非同期待ち。true の間はボタンをスピナーに差し替える。
    @State private var isCorrecting = false
    /// 訂正候補が出たときの確認ダイアログ用。nil でダイアログ非表示。
    @State private var pendingCorrection: WordNormalization?
    /// 訂正の結果お知らせ（既に正しい／確認に失敗）。nil で非表示。
    @State private var correctionNotice: String?

    var body: some View {
        List {
            // 訳語はAI生成完了時に自動補完されるため、それまではセクションごと出さない
            if !word.translation.isEmpty {
                Section {
                    Text(word.translation)
                } header: {
                    TappableEnglishText(text: "Translation")
                }
            }

            aiInfoSections

            if let example = word.exampleSentence, !example.isEmpty {
                Section {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            TappableEnglishText(text: example)
                            if let source = word.exampleSentenceSource {
                                TappableEnglishText(text: source == .textbook ? "From textbook" : "AI generated", color: .secondary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        SpeechButton(text: example, speechService: speechService, speakingText: $speakingText)
                    }
                } header: {
                    TappableEnglishText(text: "Example Sentence")
                }
            }

            if word.partOfSpeech != nil || word.grammarNote != nil {
                Section {
                    if let partOfSpeech = word.partOfSpeech {
                        LabeledContent { Text(partOfSpeech) } label: { TappableEnglishText(text: "Part of Speech") }
                    }
                    if let grammarNote = word.grammarNote {
                        LabeledContent { Text(grammarNote) } label: { TappableEnglishText(text: "Grammar") }
                    }
                } header: {
                    TappableEnglishText(text: "Part of Speech & Grammar")
                }
            }

            Section {
                let occurrences = word.occurrences.sorted { $0.occurredAt > $1.occurredAt }
                // 行タップで別レッスンへ付け替え、スワイプでその出現のみ削除できる
                ForEach(occurrences) { occurrence in
                    Button {
                        lessonPickerMode = .relink(occurrence)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(occurrence.lesson.displayTitle)
                                    .foregroundStyle(.primary)
                                Text(occurrence.lesson.schoolClass.name)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(occurrence.occurredAt, style: .date)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            WordRegistrar.unlink(occurrence, in: modelContext)
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                }
                Button {
                    lessonPickerMode = .add
                } label: {
                    Label("Add to Lesson", systemImage: "plus.circle")
                }
                .accessibilityIdentifier("wordAddToLessonButton")
            } header: {
                TappableEnglishText(text: "Appears in Lessons")
            }

            reviewStatusSection

            Section {
                LabeledContent { Text(word.registeredAt, style: .date) } label: { TappableEnglishText(text: "Added") }
            } header: {
                TappableEnglishText(text: "Details")
            }

            Section {
                // 登録済みの語を原形／正しい綴りへ後追いで直す（過去形・複数形・タイポの訂正）。
                // 正規化待ちの間はスピナー表示（二重押下防止も兼ねる）。
                if isCorrecting {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Checking…")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityIdentifier("wordCorrectProgress")
                } else {
                    Button {
                        correctWord()
                    } label: {
                        Label("Correct Word", systemImage: "textformat.abc")
                    }
                    .disabled(word.aiInfoStatus == .generating)
                    .accessibilityIdentifier("wordCorrectButton")
                }

                Button {
                    // 生成済み情報を上書きするときだけ確認を挟む。未生成・失敗時は即生成する
                    if word.aiInfoStatus == .completed {
                        isConfirmingRegenerate = true
                    } else {
                        WordAIInfoGenerator.shared.generateInBackground(for: word)
                    }
                } label: {
                    Label("Regenerate AI Info", systemImage: "arrow.clockwise")
                }
                .disabled(word.aiInfoStatus == .generating)
                .accessibilityIdentifier("wordRegenerateButton")

                Button(role: .destructive) {
                    isConfirmingDelete = true
                } label: {
                    // destructiveロールは文字だけ赤くなりアイコンがtintのままなので、アイコンも揃える
                    Label("Delete Word", systemImage: "trash")
                        .foregroundStyle(.red)
                }
                .accessibilityIdentifier("wordDeleteButton")
            }
        }
        .navigationTitle(word.text)
        // 英文中の単語タップ→登録/詳細遷移。今表示中の単語自身への遷移はスキップする
        .wordTapRegistration(currentWord: word)
        .safeAreaInset(edge: .bottom) {
            if ttsPlayback.isActive {
                TTSPlayerBar(playback: ttsPlayback)
            }
        }
        .animation(.snappy(duration: 0.2), value: ttsPlayback.isActive)
        .sheet(item: $lessonPickerMode) { mode in
            // 追加・付け替えとも、既にリンク済みのレッスンは除外して二重リンクを防ぐ
            let linkedLessonIDs = Set(word.occurrences.map(\.lesson.id))
            switch mode {
            case .add:
                WordLessonPickerView(excludedLessonIDs: linkedLessonIDs, title: "Add to Lesson") { lesson in
                    WordRegistrar.linkManually(word, to: lesson, in: modelContext)
                }
            case .relink(let occurrence):
                WordLessonPickerView(excludedLessonIDs: linkedLessonIDs, title: "Move to Lesson") { lesson in
                    WordRegistrar.relink(occurrence, to: lesson, in: modelContext)
                }
            }
        }
        .onDisappear {
            speechService.stop()
            ttsPlayback.stop()
        }
        .alert(
            "Audio Generation Failed",
            isPresented: Binding(
                get: { ttsErrorMessage != nil },
                set: { if !$0 { ttsErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(ttsErrorMessage ?? "")
        }
        .confirmationDialog(
            "Regenerate AI info?",
            isPresented: $isConfirmingRegenerate,
            titleVisibility: .visible
        ) {
            Button("Regenerate") {
                // 生成済みの上書き＝明示的な作りなおし要求なので、サーバ保存分も再生成させる
                WordAIInfoGenerator.shared.generateInBackground(for: word, regenerate: true)
            }
        } message: {
            Text("The current AI-generated info will be replaced.")
        }
        .confirmationDialog(
            "Delete this word?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                deleteWord()
            }
        } message: {
            Text("The word will be removed from the word list and all lessons.")
        }
        // 訂正候補（原形／正しい綴り）の確認。主=訂正形 / Cancel。説明（reason）のみ母語。
        .confirmationDialog(
            "Correct this word?",
            isPresented: Binding(
                get: { pendingCorrection != nil },
                set: { if !$0 { pendingCorrection = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingCorrection
        ) { normalization in
            Button("Correct to “\(normalization.effectiveLemma)”") {
                applyCorrection(to: normalization.effectiveLemma)
            }
            Button("Cancel", role: .cancel) {}
        } message: { normalization in
            Text(normalization.reason)
        }
        // 訂正不要（既に正しい）／確認失敗（オフライン等）のお知らせ
        .alert(
            "Correct Word",
            isPresented: Binding(
                get: { correctionNotice != nil },
                set: { if !$0 { correctionNotice = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(correctionNotice ?? "")
        }
    }

    /// 「Correct Word」押下時の処理。現在の綴りを正規化サービスに投げ、訂正候補（原形／正しい綴り）が
    /// あれば確認ダイアログを、無ければ「既に正しい」お知らせを出す。失敗（オフライン等）はお知らせで止める。
    private func correctWord() {
        isCorrecting = true
        let current = word.text
        let service = RemoteWordNormalizeService()
        Task {
            let normalization = try? await service.normalize(
                word: current,
                targetLanguage: WordNormalizationFlow.targetLanguage
            )
            isCorrecting = false
            guard let normalization else {
                correctionNotice = "Couldn’t check this word. Please try again."
                return
            }
            if normalization.requiresConfirmation {
                pendingCorrection = normalization
            } else {
                // canonical / 固有名詞 / 連語 / 判定不能、または候補が現在と実質同じ
                correctionNotice = "“\(current)” already looks correct."
            }
        }
    }

    /// 確認後に訂正を確定する。マージ（正規化形が既存語と一致）では表示中の語が削除されるため、
    /// 削除済みモデルの再描画を避けて先に画面を閉じる（`deleteWord` と同じ作法）。
    private func applyCorrection(to lemma: String) {
        let newText = lemma.trimmingCharacters(in: .whitespacesAndNewlines)
        let willMerge = allWords.contains {
            $0.id != word.id && $0.text.compare(newText, options: [.caseInsensitive]) == .orderedSame
        }
        if willMerge {
            dismiss()
        }
        WordRegistrar.correct(word, to: newText, in: modelContext, existingWords: allWords)
    }

    /// 復習クイズの状態（docs/plans/archive/word-memorization-quiz.md §3.5 Phase 4）。
    /// 次回復習日・ステップ・回数・正答率・最終復習日時を表示する
    private var reviewStatusSection: some View {
        let state = word.reviewState
        return Section {
            LabeledContent {
                if ReviewScheduler.isDue(state) {
                    TappableEnglishText(text: "Due today")
                        .foregroundStyle(.orange)
                        .fontWeight(.medium)
                } else {
                    Text(state.dueDate, style: .date)
                }
            } label: {
                TappableEnglishText(text: "Next Review")
            }
            .accessibilityIdentifier("wordReviewNextRow")
            // 現在の周回の習熟度（100%到達で次回復習日に進み、0%から再スタート）
            LabeledContent { Text("\(state.masteryPercent)%") } label: { TappableEnglishText(text: "Mastery") }
                .accessibilityIdentifier("wordReviewMasteryRow")
            // stepIndex は「次の正解で適用される間隔」のインデックス（0始まり）
            let step = min(state.stepIndex, ReviewScheduler.stepIntervalsInDays.count - 1)
            LabeledContent {
                Text("\(step + 1) / \(ReviewScheduler.stepIntervalsInDays.count)"
                    + " (+\(ReviewScheduler.stepIntervalsInDays[step]) days)")
            } label: {
                TappableEnglishText(text: "Step")
            }
            .accessibilityIdentifier("wordReviewStepRow")
            LabeledContent { Text("\(state.reviewCount)") } label: { TappableEnglishText(text: "Reviews") }
            if state.reviewCount > 0 {
                let percent = Int((Double(state.correctCount) / Double(state.reviewCount) * 100).rounded())
                LabeledContent { Text("\(percent)% (\(state.correctCount)/\(state.reviewCount))") } label: { TappableEnglishText(text: "Accuracy") }
                    .accessibilityIdentifier("wordReviewAccuracyRow")
                if let lastReviewedAt = state.lastReviewedAt {
                    LabeledContent { Text(lastReviewedAt, style: .date) } label: { TappableEnglishText(text: "Last Reviewed") }
                }
            }
        } header: {
            TappableEnglishText(text: "Review")
        }
    }

    /// レッスン選択シートの提示モード（追加 / 既存出現の付け替え）
    private enum LessonPickerMode: Identifiable {
        case add
        case relink(WordOccurrence)

        var id: String {
            switch self {
            case .add: return "add"
            case .relink(let occurrence): return occurrence.id.uuidString
            }
        }
    }

    /// 単語本体を削除して一覧に戻る。cascade で全レッスンの WordOccurrence も消える
    private func deleteWord() {
        dismiss()
        modelContext.delete(word)
        // autosave任せだと直後にアプリが強制終了された場合に失われるため明示的に保存する
        modelContext.saveOrLog()
    }

    /// AI生成情報のセクション群（ステータスに応じて表示を切り替える）
    @ViewBuilder
    private var aiInfoSections: some View {
        switch word.aiInfoStatus {
        case .none:
            Section {
                TappableEnglishText(text: "AI word info has not been generated yet", color: .secondary)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("wordAIInfoNoneLabel")
                Button("Generate AI Word Info") {
                    WordAIInfoGenerator.shared.generateInBackground(for: word)
                }
                .accessibilityIdentifier("wordAIInfoGenerateButton")
            } header: {
                TappableEnglishText(text: "AI Word Info")
            }
        case .generating:
            Section {
                HStack(spacing: 12) {
                    ProgressView()
                    TappableEnglishText(text: "Generating…", color: .secondary)
                        .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("wordAIInfoGeneratingLabel")
            } header: {
                TappableEnglishText(text: "AI Word Info")
            }
        case .failed:
            Section {
                Label("Generation failed", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("wordAIInfoFailedLabel")
                if let errorMessage = word.aiInfoErrorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Button("Retry") {
                    WordAIInfoGenerator.shared.generateInBackground(for: word)
                }
                .accessibilityIdentifier("wordAIInfoRetryButton")
            } header: {
                TappableEnglishText(text: "AI Word Info")
            }
        case .completed:
            if let info = word.aiInfo {
                WordAIInfoSections(
                    info: info,
                    wordText: word.text,
                    // イラストのキャッシュキーはAI情報を生成した言語に揃える（未記録の旧データは設定値）
                    targetLanguage: word.aiInfoLanguage
                        ?? UserDefaults.standard.string(forKey: AppSettingsKeys.targetLanguageCode)
                        ?? AppSettingsKeys.defaultTargetLanguageCode,
                    speechService: speechService,
                    speakingText: $speakingText,
                    ttsPlayback: ttsPlayback,
                    ttsErrorMessage: $ttsErrorMessage
                )
            }
        }
    }
}

/// AI生成情報の表示セクション群。空の項目（nil・空配列）はセクションごと非表示にする。
private struct WordAIInfoSections: View {
    let info: WordAIInfo
    let wordText: String
    let targetLanguage: String
    @ObservedObject var speechService: SpeechService
    @Binding var speakingText: String?
    @ObservedObject var ttsPlayback: TTSPlaybackService
    @Binding var ttsErrorMessage: String?

    var body: some View {
        Section {
            WordIllustrationRow(wordText: wordText, targetLanguage: targetLanguage)
        } header: {
            TappableEnglishText(text: "Illustration")
        }

        Section {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(info.pronunciation.ipa)
                    if let syllables = info.pronunciation.syllables, !syllables.isEmpty {
                        Text(syllables)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                TTSButton(text: wordText, playback: ttsPlayback, errorMessage: $ttsErrorMessage)
            }
            badgeRow
        } header: {
            TappableEnglishText(text: "Pronunciation")
        }

        if !info.senses.isEmpty {
            Section {
                ForEach(Array(info.senses.enumerated()), id: \.offset) { index, sense in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("\(index + 1).")
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8) {
                                    Text(sense.partOfSpeech)
                                        .font(.caption)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(.quaternary, in: Capsule())
                                    Text(sense.meaning)
                                        .fontWeight(.semibold)
                                }
                                HStack(alignment: .top) {
                                    TappableEnglishText(text: sense.englishDefinition, color: .secondary)
                                        .font(.subheadline)
                                    Spacer()
                                    TTSButton(text: sense.englishDefinition, playback: ttsPlayback, errorMessage: $ttsErrorMessage)
                                }
                                if let note = sense.note, !note.isEmpty {
                                    Text(note)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                TappableEnglishText(text: "Meanings")
            }
        }

        if !info.inflections.isEmpty {
            Section {
                ForEach(Array(info.inflections.enumerated()), id: \.offset) { _, inflection in
                    LabeledContent {
                        TappableEnglishText(text: inflection.text)
                    } label: {
                        TappableEnglishText(text: Self.englishInflectionLabel(inflection.form))
                    }
                }
            } header: {
                TappableEnglishText(text: "Word Forms")
            }
        }

        if !info.examples.isEmpty {
            Section {
                ForEach(Array(info.examples.enumerated()), id: \.offset) { _, example in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            TappableEnglishText(text: example.english)
                            Text(example.translation)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        TTSButton(text: example.english, playback: ttsPlayback, errorMessage: $ttsErrorMessage)
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                TappableEnglishText(text: "Examples")
            }
        }

        if !info.collocations.isEmpty {
            Section {
                ForEach(info.collocations, id: \.self) { collocation in
                    HStack {
                        TappableEnglishText(text: collocation)
                        Spacer()
                        SpeechButton(text: collocation, speechService: speechService, speakingText: $speakingText)
                    }
                }
            } header: {
                TappableEnglishText(text: "Collocations")
            }
        }

        if !info.synonyms.isEmpty || !info.antonyms.isEmpty {
            Section {
                if !info.synonyms.isEmpty {
                    wordListRow(title: "Synonyms", words: info.synonyms)
                }
                if !info.antonyms.isEmpty {
                    wordListRow(title: "Antonyms", words: info.antonyms)
                }
            } header: {
                TappableEnglishText(text: "Synonyms & Antonyms")
            }
        }

        if hasNotes {
            Section {
                if let usageNote = info.usageNote, !usageNote.isEmpty {
                    noteRow(title: "Usage Notes", text: usageNote)
                }
                if let etymology = info.etymology, !etymology.isEmpty {
                    noteRow(title: "Etymology & Memory Hints", text: etymology)
                }
                if let commonMistakes = info.commonMistakes, !commonMistakes.isEmpty {
                    noteRow(title: "Common Mistakes", text: commonMistakes)
                }
            } header: {
                TappableEnglishText(text: "Study Notes")
            }
        }
    }

    /// CEFRレベル・使用域のバッジ行（どちらも無ければ非表示）
    @ViewBuilder
    private var badgeRow: some View {
        let cefr = info.cefrLevel?.trimmingCharacters(in: .whitespaces) ?? ""
        let register = info.register?.trimmingCharacters(in: .whitespaces) ?? ""
        if !cefr.isEmpty || !register.isEmpty {
            HStack(spacing: 8) {
                if !cefr.isEmpty {
                    Text("CEFR \(cefr)")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.tint.opacity(0.15), in: Capsule())
                }
                if !register.isEmpty {
                    Text(register)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.quaternary, in: Capsule())
                }
            }
        }
    }

    private var hasNotes: Bool {
        [info.usageNote, info.etymology, info.commonMistakes]
            .contains { !($0 ?? "").isEmpty }
    }

    /// 類義語・反意語のような単語リスト行。カンマ区切りのリスト全体を読み上げ対象にしつつ、
    /// 各語はタップで登録/詳細遷移できる（区切りのカンマ・空白は非単語として素通し）。
    private func wordListRow(title: String, words: [String]) -> some View {
        let joined = words.joined(separator: ", ")
        return HStack(alignment: .top) {
            LabeledContent {
                TappableEnglishText(text: joined)
            } label: {
                TappableEnglishText(text: title)
            }
            SpeechButton(text: joined, speechService: speechService, speakingText: $speakingText)
        }
    }

    /// 学習ノート行。本文は英語・母語が混在しうるが、英単語だけがリンク化されるため安全にタップできる。
    private func noteRow(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            TappableEnglishText(text: title, color: .secondary)
                .font(.caption)
                .foregroundStyle(.secondary)
            TappableEnglishText(text: text)
        }
        .padding(.vertical, 2)
    }

    /// 語形変化のラベル。旧データは母語（日本語）で保存されているため、
    /// 既知の日本語ラベルは英語の文法用語に変換して表示する（未知のものはそのまま）。
    static func englishInflectionLabel(_ form: String) -> String {
        let map: [String: String] = [
            "三人称単数現在形": "third-person singular",
            "三人称単数現在": "third-person singular",
            "三人称単数": "third-person singular",
            "過去形": "past tense",
            "過去分詞": "past participle",
            "現在分詞": "present participle",
            "動名詞": "gerund",
            "複数形": "plural",
            "比較級": "comparative",
            "最上級": "superlative",
            "原形": "base form",
        ]
        return map[form] ?? form
    }
}

/// 単語の意味を直感的に伝えるAI生成イラスト（GPT Image 2）の行。
/// 生成はAI単語情報の完成に続けて WordIllustrationGenerator が自動で開始しており、
/// この行は端末ローカルに保存済みなら即表示、生成中ならスピナーを出して完成し次第
/// 画像に差し替える。未着手（AI情報だけ生成済みの既存単語など）なら行の表示時に生成を
/// 開始する。失敗時はエラーメッセージ + Retry ボタン。生成した画像はサーバと端末ローカル
/// の両方に保存され、2回目以降の生成はサーバキャッシュ、再訪時の表示は端末ローカルから行われる。
private struct WordIllustrationRow: View {
    let wordText: String
    let targetLanguage: String

    // 生成そのものは共有の WordIllustrationGenerator が担う（AI情報生成完了後の自動生成と共用、
    // キー単位で多重リクエスト排他）。この行は生成状態を観測して表示を切り替えるだけ。
    // body は image / inFlight / failures を読んで分岐するため、生成完了・失敗で確実に再描画される
    @ObservedObject private var generator = WordIllustrationGenerator.shared
    @State private var image: UIImage?

    var body: some View {
        let isGenerating = generator.isGenerating(word: wordText, targetLanguage: targetLanguage)
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                    .accessibilityLabel("Illustration of \(wordText)")
                    .accessibilityIdentifier("wordIllustrationImage")
            } else if let errorMessage = generator.failureMessage(word: wordText, targetLanguage: targetLanguage) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                    Button {
                        generator.generateIfNeeded(word: wordText, targetLanguage: targetLanguage)
                    } label: {
                        Label("Retry", systemImage: "arrow.clockwise")
                    }
                    .accessibilityIdentifier("wordIllustrationRetryButton")
                }
            } else {
                HStack(spacing: 12) {
                    ProgressView()
                    TappableEnglishText(text: "Generating illustration…", color: .secondary)
                        .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("wordIllustrationGeneratingLabel")
            }
        }
        // 表示時と生成完了時（inFlight から消えた時）にローカルファイルを読み込む。
        // ファイルも失敗記録も無ければここから生成を開始する（AI情報だけ生成済みの既存単語向け）
        .task(id: isGenerating) {
            guard image == nil, !isGenerating else { return }
            if let localURL = WordIllustrationStore.localURL(word: wordText, targetLanguage: targetLanguage),
               let cached = UIImage(contentsOfFile: localURL.path) {
                image = cached
            } else if generator.failureMessage(word: wordText, targetLanguage: targetLanguage) == nil {
                generator.generateIfNeeded(word: wordText, targetLanguage: targetLanguage)
            }
        }
    }
}

/// 英文の行末に置く読み上げボタン。端末内蔵TTS（SpeechService）で読み上げ、再生中は停止ボタンになる。
private struct SpeechButton: View {
    let text: String
    @ObservedObject var speechService: SpeechService
    @Binding var speakingText: String?

    private var isActive: Bool {
        speechService.isSpeaking && speakingText == text
    }

    var body: some View {
        Button {
            if isActive {
                speechService.stop()
                speakingText = nil
            } else {
                speakingText = text
                speechService.speak(text)
            }
        } label: {
            Image(systemName: isActive ? "stop.fill" : "speaker.wave.2.fill")
                .foregroundStyle(.tint)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(isActive ? "Stop" : "Speak")
    }
}
