import SwiftUI
import SwiftData

struct WordDetailView: View {
    let word: Word

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var isConfirmingRegenerate = false
    @State private var isConfirmingDelete = false
    @StateObject private var speechService = SpeechService()
    @State private var speakingText: String?
    @StateObject private var ttsPlayback = TTSPlaybackService()
    @State private var ttsErrorMessage: String?

    var body: some View {
        List {
            // 訳語はAI生成完了時に自動補完されるため、それまではセクションごと出さない
            if !word.translation.isEmpty {
                Section("Translation") {
                    Text(word.translation)
                }
            }

            aiInfoSections

            if let example = word.exampleSentence, !example.isEmpty {
                Section("Example Sentence") {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(example)
                            if let source = word.exampleSentenceSource {
                                Text(source == .textbook ? "From textbook" : "AI generated")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        SpeechButton(text: example, speechService: speechService, speakingText: $speakingText)
                    }
                }
            }

            if word.partOfSpeech != nil || word.grammarNote != nil {
                Section("Part of Speech & Grammar") {
                    if let partOfSpeech = word.partOfSpeech {
                        LabeledContent("Part of Speech", value: partOfSpeech)
                    }
                    if let grammarNote = word.grammarNote {
                        LabeledContent("Grammar", value: grammarNote)
                    }
                }
            }

            Section("Appears in Lessons") {
                let occurrences = word.occurrences.sorted { $0.occurredAt > $1.occurredAt }
                if occurrences.isEmpty {
                    Text("Not linked to any lesson")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(occurrences) { occurrence in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(occurrence.lesson.title)
                                Text(occurrence.lesson.schoolClass.name)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(occurrence.occurredAt, style: .date)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            reviewStatusSection

            Section("Details") {
                LabeledContent("Added") {
                    Text(word.registeredAt, style: .date)
                }
            }

            Section {
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
        .safeAreaInset(edge: .bottom) {
            if ttsPlayback.isActive {
                TTSPlayerBar(playback: ttsPlayback)
            }
        }
        .animation(.snappy(duration: 0.2), value: ttsPlayback.isActive)
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
    }

    /// 復習クイズの状態（docs/plans/archive/word-memorization-quiz.md §3.5 Phase 4）。
    /// 次回復習日・ステップ・回数・正答率・最終復習日時を表示する
    private var reviewStatusSection: some View {
        let state = word.reviewState
        return Section("Review") {
            LabeledContent("Next Review") {
                if ReviewScheduler.isDue(state) {
                    Text("Due today")
                        .foregroundStyle(.orange)
                        .fontWeight(.medium)
                } else {
                    Text(state.dueDate, style: .date)
                }
            }
            .accessibilityIdentifier("wordReviewNextRow")
            // 現在の周回の習熟度（100%到達で次回復習日に進み、0%から再スタート）
            LabeledContent("Mastery", value: "\(state.masteryPercent)%")
                .accessibilityIdentifier("wordReviewMasteryRow")
            // stepIndex は「次の正解で適用される間隔」のインデックス（0始まり）
            let step = min(state.stepIndex, ReviewScheduler.stepIntervalsInDays.count - 1)
            LabeledContent(
                "Step",
                value: "\(step + 1) / \(ReviewScheduler.stepIntervalsInDays.count)"
                    + " (+\(ReviewScheduler.stepIntervalsInDays[step]) days)"
            )
            .accessibilityIdentifier("wordReviewStepRow")
            LabeledContent("Reviews", value: "\(state.reviewCount)")
            if state.reviewCount > 0 {
                let percent = Int((Double(state.correctCount) / Double(state.reviewCount) * 100).rounded())
                LabeledContent("Accuracy", value: "\(percent)% (\(state.correctCount)/\(state.reviewCount))")
                    .accessibilityIdentifier("wordReviewAccuracyRow")
                if let lastReviewedAt = state.lastReviewedAt {
                    LabeledContent("Last Reviewed") {
                        Text(lastReviewedAt, style: .date)
                    }
                }
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
            Section("AI Word Info") {
                Text("AI word info has not been generated yet")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("wordAIInfoNoneLabel")
                Button("Generate AI Word Info") {
                    WordAIInfoGenerator.shared.generateInBackground(for: word)
                }
                .accessibilityIdentifier("wordAIInfoGenerateButton")
            }
        case .generating:
            Section("AI Word Info") {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Generating…")
                        .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("wordAIInfoGeneratingLabel")
            }
        case .failed:
            Section("AI Word Info") {
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
        Section("Illustration") {
            WordIllustrationRow(wordText: wordText, targetLanguage: targetLanguage)
        }

        Section("Pronunciation") {
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
        }

        if !info.senses.isEmpty {
            Section("Meanings") {
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
                                    Text(sense.englishDefinition)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
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
            }
        }

        if !info.inflections.isEmpty {
            Section("Word Forms") {
                ForEach(Array(info.inflections.enumerated()), id: \.offset) { _, inflection in
                    LabeledContent(inflection.form, value: inflection.text)
                }
            }
        }

        if !info.examples.isEmpty {
            Section("Examples") {
                ForEach(Array(info.examples.enumerated()), id: \.offset) { _, example in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(example.english)
                            Text(example.translation)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        TTSButton(text: example.english, playback: ttsPlayback, errorMessage: $ttsErrorMessage)
                    }
                    .padding(.vertical, 2)
                }
            }
        }

        if !info.collocations.isEmpty {
            Section("Collocations") {
                ForEach(info.collocations, id: \.self) { collocation in
                    HStack {
                        Text(collocation)
                        Spacer()
                        SpeechButton(text: collocation, speechService: speechService, speakingText: $speakingText)
                    }
                }
            }
        }

        if !info.synonyms.isEmpty || !info.antonyms.isEmpty {
            Section("Synonyms & Antonyms") {
                if !info.synonyms.isEmpty {
                    wordListRow(title: "Synonyms", words: info.synonyms)
                }
                if !info.antonyms.isEmpty {
                    wordListRow(title: "Antonyms", words: info.antonyms)
                }
            }
        }

        if hasNotes {
            Section("Study Notes") {
                if let usageNote = info.usageNote, !usageNote.isEmpty {
                    noteRow(title: "Usage Notes", text: usageNote)
                }
                if let etymology = info.etymology, !etymology.isEmpty {
                    noteRow(title: "Etymology & Memory Hints", text: etymology)
                }
                if let commonMistakes = info.commonMistakes, !commonMistakes.isEmpty {
                    noteRow(title: "Common Mistakes", text: commonMistakes)
                }
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

    /// 類義語・反意語のような単語リスト行。カンマ区切りのリスト全体を読み上げ対象にする。
    private func wordListRow(title: String, words: [String]) -> some View {
        let joined = words.joined(separator: ", ")
        return HStack(alignment: .top) {
            LabeledContent(title, value: joined)
            SpeechButton(text: joined, speechService: speechService, speakingText: $speakingText)
        }
    }

    private func noteRow(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(text)
        }
        .padding(.vertical, 2)
    }
}

/// 単語の意味を直感的に伝えるAI生成イラスト（GPT Image 2）の行。
/// 端末ローカルに保存済みなら即表示、未生成なら行の表示と同時にバックグラウンドで
/// 自動生成を開始し（スピナー表示）、完了したら画像表示に切り替わる。失敗時は
/// エラーメッセージ + Retry ボタン。生成した画像はサーバと端末ローカルの両方に保存され、
/// 2回目以降の生成はサーバキャッシュ、再訪時の表示は端末ローカルから行われる。
private struct WordIllustrationRow: View {
    let wordText: String
    let targetLanguage: String

    @State private var isGenerating = false
    @State private var errorMessage: String?

    var body: some View {
        // 存在チェックのみで軽量。生成完了で isGenerating が変わると再評価されて画像表示に切り替わる
        let localURL = WordIllustrationStore.localURL(word: wordText, targetLanguage: targetLanguage)
        if let localURL, let uiImage = UIImage(contentsOfFile: localURL.path) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                .accessibilityLabel("Illustration of \(wordText)")
                .accessibilityIdentifier("wordIllustrationImage")
        } else if let errorMessage {
            VStack(alignment: .leading, spacing: 6) {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                Button {
                    generate()
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .accessibilityIdentifier("wordIllustrationRetryButton")
            }
        } else {
            HStack(spacing: 12) {
                ProgressView()
                Text("Generating illustration…")
                    .foregroundStyle(.secondary)
            }
            .accessibilityIdentifier("wordIllustrationGeneratingLabel")
            // 未生成なら表示と同時にバックグラウンドで生成を始める（isGenerating 中は generate() 側で弾く）
            .onAppear(perform: generate)
        }
    }

    /// サーバで生成（保存済みならサーバキャッシュ返却）したPNGを端末ローカルに保存する
    private func generate() {
        guard !isGenerating else { return }
        isGenerating = true
        errorMessage = nil
        Task {
            defer { isGenerating = false }
            do {
                let data = try await RemoteWordIllustrationService()
                    .fetchIllustration(word: wordText, targetLanguage: targetLanguage, senseIndex: 0)
                try WordIllustrationStore.save(data: data, word: wordText, targetLanguage: targetLanguage)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// サーバTTS（Gemini）の生成→再生ボタン。ttsModel が On-Device でも常にサーバTTSを使う専用ボタン。
/// 未生成（端末ローカルにファイルなし）なら生成ボタン、生成中はスピナー、
/// 生成済みなら再生/停止ボタンになる。生成した音声はサーバと端末ローカルの両方に保存され、
/// 2回目以降の生成はサーバキャッシュ、再訪時の再生は端末ローカルから行われる。
private struct TTSButton: View {
    let text: String
    @ObservedObject var playback: TTSPlaybackService
    @Binding var errorMessage: String?

    @AppStorage(AppSettingsKeys.ttsModel) private var model = AppSettingsKeys.defaultTTSModel
    @State private var isGenerating = false

    /// ttsModel が "local"（On-Device）のときはサーバが受け付けるモデルに読み替える
    private var serverModel: String {
        model == "local" ? AppSettingsKeys.fallbackServerTTSModel : model
    }

    private struct RequestBody: Encodable {
        let text: String
        let model: String
    }

    var body: some View {
        // 存在チェックのみで軽量。model 設定を変えるとキーが変わり「未生成」に戻る
        let localURL = TTSAudioStore.localURL(text: text, model: serverModel)
        if isGenerating {
            ProgressView()
        } else if let localURL {
            // 一時停止中もこの行の音源がロードされたままなので、停止（アンロード）ボタンを出す
            let isActive = playback.currentURL == localURL
            Button {
                if isActive {
                    playback.stop()
                } else {
                    playback.play(url: localURL)
                }
            } label: {
                Image(systemName: isActive ? "stop.fill" : "speaker.wave.2.fill")
                    .foregroundStyle(.tint)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(isActive ? "Stop" : "Play AI Audio")
        } else {
            Button {
                generate()
            } label: {
                Image(systemName: "waveform.badge.plus")
                    .foregroundStyle(.tint)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Generate AI Audio")
        }
    }

    /// サーバで合成（保存済みならサーバキャッシュ返却）した音声を端末ローカルに保存する
    private func generate() {
        guard !isGenerating else { return }
        isGenerating = true
        Task {
            defer { isGenerating = false }
            do {
                let data = try await BackendAPI.post(
                    path: "api/tts",
                    body: RequestBody(text: text, model: serverModel)
                )
                try TTSAudioStore.save(data: data, text: text, model: serverModel)
            } catch {
                errorMessage = error.localizedDescription
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
