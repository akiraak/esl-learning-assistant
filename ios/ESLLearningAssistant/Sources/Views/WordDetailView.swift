import SwiftUI
import SwiftData

struct WordDetailView: View {
    let word: Word

    @State private var isConfirmingRegenerate = false
    @StateObject private var speechService = SpeechService()
    @State private var speakingText: String?

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

            Section("Details") {
                LabeledContent("Added") {
                    Text(word.registeredAt, style: .date)
                }
                LabeledContent("Reviews", value: "\(word.reviewState.reviewCount)")
            }
        }
        .navigationTitle(word.text)
        .onDisappear {
            speechService.stop()
        }
        .toolbar {
            if word.aiInfoStatus == .completed {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Regenerate AI Info") {
                            isConfirmingRegenerate = true
                        }
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                    .accessibilityIdentifier("wordDetailMenu")
                }
            }
        }
        .confirmationDialog(
            "Regenerate AI info?",
            isPresented: $isConfirmingRegenerate,
            titleVisibility: .visible
        ) {
            Button("Regenerate") {
                WordAIInfoGenerator.shared.generateInBackground(for: word)
            }
        } message: {
            Text("The current AI-generated info will be replaced.")
        }
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
                    speechService: speechService,
                    speakingText: $speakingText
                )
            }
        }
    }
}

/// AI生成情報の表示セクション群。空の項目（nil・空配列）はセクションごと非表示にする。
private struct WordAIInfoSections: View {
    let info: WordAIInfo
    let wordText: String
    @ObservedObject var speechService: SpeechService
    @Binding var speakingText: String?

    var body: some View {
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
                SpeechButton(text: wordText, speechService: speechService, speakingText: $speakingText)
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
                                    SpeechButton(text: sense.englishDefinition, speechService: speechService, speakingText: $speakingText)
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
                        SpeechButton(text: example.english, speechService: speechService, speakingText: $speakingText)
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
