import SwiftUI
import SwiftData

/// 復習クイズのセッション画面。1問ずつ出題 → 回答 → 正誤フィードバック → 次へ。
/// 上限は1セッション20問（超過分は次セッションで続けられる）。
/// セッション内で不正解だった単語は最後にもう一度出題する。reviewState への反映は
/// 各単語の初回解答のみで、再出題は表示のみ（ReviewScheduler.reviewed を二重適用しない）。
///
/// 問題はサーバ保存のもののみを使う（docs/plans/archive/quiz-questions-server-storage.md）。
/// セッション開始時に /api/quiz-questions/query でまとめて取得し、単語ごとに
/// 比率調整（FormatSelector）で形式を選び、その形式の複数バリエーションから
/// ランダムに1問を出題する。サーバに問題が無い単語は出題せずスキップする。
struct ReviewSessionView: View {
    /// 今日の復習対象（呼び出し側で ReviewScheduler.isDue フィルタ済み）
    let dueWords: [Word]

    /// 1セッションの出題上限
    static let sessionLimit = 20

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    // イラスト4択の誤答単語など、出題対象外の単語のイラスト・言語解決に使う
    @Query private var allWords: [Word]

    @StateObject private var speechService = SpeechService()
    @StateObject private var ttsPlayback = TTSPlaybackService()
    @AppStorage(AppSettingsKeys.ttsVoice) private var ttsVoice = AppSettingsKeys.defaultTTSVoice
    @AppStorage(AppSettingsKeys.ttsModel) private var ttsModel = AppSettingsKeys.defaultTTSModel

    @State private var hasStarted = false
    @State private var isLoading = true
    @State private var loadErrorMessage: String?
    @State private var questionsByWordID: [UUID: [ReviewQuestion]] = [:]
    /// サーバに問題が無くスキップした due 単語の数（サマリーで知らせる）
    @State private var skippedWordCount = 0
    @State private var mainQueue: [Word] = []
    @State private var retryQueue: [Word] = []
    @State private var current: CurrentQuestion?
    @State private var sessionCounts: [ReviewQuestionFormat: Int] = [:]
    /// 解答済みの問題数（再出題を含む。進捗表示用）
    @State private var completedCount = 0
    /// 初回解答の数と正解数（サマリー表示用。再出題は含まない）
    @State private var firstAnswerCount = 0
    @State private var firstCorrectCount = 0
    @State private var typedAnswer = ""
    @State private var selectedChoiceIndex: Int?
    @State private var feedback: Feedback?
    @State private var isFinished = false
    @FocusState private var isAnswerFieldFocused: Bool

    private struct CurrentQuestion {
        var word: Word
        var question: ReviewQuestion
        var isRetry: Bool
    }

    private struct Feedback {
        var isCorrect: Bool
        var correctAnswer: String
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    loadingView
                } else if let loadErrorMessage {
                    loadFailedView(loadErrorMessage)
                } else if isFinished {
                    summaryView
                } else if let current {
                    questionView(current)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                    .accessibilityIdentifier("reviewCloseButton")
                }
            }
        }
        .interactiveDismissDisabled()
        .onAppear(perform: startSession)
        .onDisappear {
            speechService.stop()
            ttsPlayback.stop()
        }
    }

    // MARK: - ローディング・取得失敗

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading questions…")
                .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("reviewLoadingLabel")
    }

    private func loadFailedView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Couldn't Load Questions")
                .font(.title3)
                .fontWeight(.semibold)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Retry") {
                isLoading = true
                loadErrorMessage = nil
                Task { await loadQuestions() }
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("reviewRetryLoadButton")
        }
        .padding()
    }

    // MARK: - 出題画面

    private func questionView(_ item: CurrentQuestion) -> some View {
        VStack(spacing: 0) {
            progressHeader

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(item.question.instruction)
                        .font(.headline)

                    if let audioText = item.question.audioText {
                        audioReplayButton(audioText)
                    }

                    if let illustrationWord = item.question.promptIllustrationWord {
                        promptIllustration(illustrationWord)
                    }

                    if let displayText = item.question.displayText {
                        Text(displayText)
                            .font(.title3)
                            .fontWeight(.medium)
                    }

                    answerArea(item)

                    if let feedback {
                        feedbackCard(feedback, item: item)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }

            if feedback != nil {
                nextButton
            }
        }
    }

    private var progressHeader: some View {
        let remaining = mainQueue.count + retryQueue.count + (current != nil ? 1 : 0)
        let total = completedCount + remaining
        return VStack(spacing: 4) {
            ProgressView(value: Double(completedCount), total: Double(max(total, 1)))
            Text("\(min(completedCount + 1, total)) / \(total)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    /// 音声出題の再生ボタン（何度でも聞き直せる）
    private func audioReplayButton(_ text: String) -> some View {
        Button {
            playAudio(text)
        } label: {
            Label("Play Audio", systemImage: "speaker.wave.2.fill")
                .font(.title3)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.tint.opacity(0.12), in: Capsule())
        }
        .accessibilityIdentifier("reviewPlayAudioButton")
    }

    @ViewBuilder
    private func promptIllustration(_ wordText: String) -> some View {
        if let image = illustrationImage(for: wordText) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 240)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - 回答エリア

    @ViewBuilder
    private func answerArea(_ item: CurrentQuestion) -> some View {
        switch item.question.answer {
        case .choices(let options, let correctIndex):
            choiceButtons(options: options, correctIndex: correctIndex)
        case .illustrationChoices(let options, let correctIndex):
            illustrationChoiceGrid(options: options, correctIndex: correctIndex)
        case .typing:
            typingArea(item)
        }
    }

    private func choiceButtons(options: [String], correctIndex: Int) -> some View {
        VStack(spacing: 10) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                Button {
                    submitChoice(index, correctIndex: correctIndex, correctAnswer: options[correctIndex])
                } label: {
                    Text(option)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 14)
                        .background(choiceBackground(index: index, correctIndex: correctIndex), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(.quaternary)
                        )
                }
                .buttonStyle(.plain)
                .disabled(feedback != nil)
                .accessibilityIdentifier("reviewChoiceButton\(index)")
            }
        }
    }

    private func illustrationChoiceGrid(options: [String], correctIndex: Int) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                Button {
                    submitChoice(index, correctIndex: correctIndex, correctAnswer: options[correctIndex])
                } label: {
                    Group {
                        if let image = illustrationImage(for: option) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                        } else {
                            // イラストが読めない場合の保険（単語テキストで代替）
                            Text(option)
                                .padding()
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .background(choiceBackground(index: index, correctIndex: correctIndex), in: RoundedRectangle(cornerRadius: 12))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(
                                feedback != nil && index == correctIndex ? Color.green : Color(.separator),
                                lineWidth: feedback != nil && index == correctIndex ? 3 : 1
                            )
                    )
                }
                .buttonStyle(.plain)
                .disabled(feedback != nil)
                .accessibilityIdentifier("reviewChoiceButton\(index)")
            }
        }
    }

    /// 回答後は正答を緑・選んだ誤答を赤で塗って見せる
    private func choiceBackground(index: Int, correctIndex: Int) -> Color {
        guard feedback != nil else { return Color(.secondarySystemBackground) }
        if index == correctIndex { return .green.opacity(0.25) }
        if index == selectedChoiceIndex { return .red.opacity(0.25) }
        return Color(.secondarySystemBackground)
    }

    @ViewBuilder
    private func typingArea(_ item: CurrentQuestion) -> some View {
        VStack(spacing: 12) {
            TextField("Type your answer", text: $typedAnswer, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($isAnswerFieldFocused)
                .disabled(feedback != nil)
                .accessibilityIdentifier("reviewTypedAnswerField")

            if feedback == nil {
                Button {
                    submitTypedAnswer(item)
                } label: {
                    Text("Answer")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(typedAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("reviewSubmitButton")
            }
        }
    }

    // MARK: - フィードバック

    private func feedbackCard(_ feedback: Feedback, item: CurrentQuestion) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(
                feedback.isCorrect ? "Correct!" : "Incorrect",
                systemImage: feedback.isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill"
            )
            .font(.title3)
            .fontWeight(.semibold)
            .foregroundStyle(feedback.isCorrect ? .green : .red)
            .accessibilityIdentifier(feedback.isCorrect ? "reviewFeedbackCorrect" : "reviewFeedbackIncorrect")

            if !feedback.isCorrect {
                Text("Answer: \(feedback.correctAnswer)")
                    .fontWeight(.medium)
            }

            Divider()

            // 正誤にかかわらず単語のまとめを見せて記憶を強化する（プラン §3.5）
            HStack(alignment: .firstTextBaseline) {
                Text(item.word.text)
                    .font(.title3)
                    .fontWeight(.semibold)
                if !item.word.translation.isEmpty {
                    Text(item.word.translation)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    playAudio(item.word.text)
                } label: {
                    Image(systemName: "speaker.wave.2.fill")
                        .foregroundStyle(.tint)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Speak word")
            }

            if let example = item.word.aiInfo?.examples.first {
                VStack(alignment: .leading, spacing: 2) {
                    Text(example.english)
                        .font(.subheadline)
                    Text(example.translation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let image = illustrationImage(for: item.word.text) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private var nextButton: some View {
        Button {
            advance()
        } label: {
            Text(mainQueue.isEmpty && retryQueue.isEmpty ? "Finish" : "Next")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .padding()
        .accessibilityIdentifier("reviewNextButton")
    }

    // MARK: - サマリー

    @ViewBuilder
    private var summaryView: some View {
        if firstAnswerCount == 0 && skippedWordCount > 0 {
            // 全単語がスキップ（問題未生成）だった場合。自己修復トリガ済みなので時間を置けば出題できる
            VStack(spacing: 16) {
                Image(systemName: "hourglass")
                    .font(.system(size: 56))
                    .foregroundStyle(.secondary)
                Text("Preparing Questions")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("reviewPreparingLabel")
                Text("Questions for today's words are being generated on the server. Please try again in a moment.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Button {
                    dismiss()
                } label: {
                    Text("Close")
                        .frame(maxWidth: 200)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("reviewDoneButton")
            }
            .padding()
        } else {
            VStack(spacing: 16) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.green)
                Text("Session Complete")
                    .font(.title2)
                    .fontWeight(.semibold)
                if firstAnswerCount > 0 {
                    Text("\(firstCorrectCount) of \(firstAnswerCount) correct")
                        .foregroundStyle(.secondary)
                }
                if skippedWordCount > 0 {
                    Text("\(skippedWordCount) word\(skippedWordCount == 1 ? "" : "s") skipped (questions being prepared)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if dueWords.count > Self.sessionLimit {
                    Text("\(dueWords.count - Self.sessionLimit) more words are still due today.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Button {
                    dismiss()
                } label: {
                    Text("Done")
                        .frame(maxWidth: 200)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("reviewDoneButton")
            }
            .padding()
        }
    }

    // MARK: - セッション進行

    private func startSession() {
        guard !hasStarted else { return }
        hasStarted = true
        Task { await loadQuestions() }
    }

    /// セッション対象（上限20語）の問題をサーバからまとめて取得する。
    /// 問題が無い単語はスキップし、サーバ生成の自己修復トリガだけ投げておく。
    private func loadQuestions() async {
        let candidates = Array(dueWords.prefix(Self.sessionLimit))
        guard !candidates.isEmpty else {
            isLoading = false
            isFinished = true
            return
        }

        // 単語の言語（aiInfoLanguage）ごとにまとめて取得する（通常は1言語）
        var wordsByLanguage: [String: [Word]] = [:]
        for word in candidates {
            wordsByLanguage[targetLanguage(for: word), default: []].append(word)
        }

        var fetched: [UUID: [ReviewQuestion]] = [:]
        do {
            let service = RemoteQuizQuestionService()
            for (language, words) in wordsByLanguage {
                let questions = try await service.fetchQuestions(
                    words: words.map(\.text), targetLanguage: language
                )
                for word in words {
                    if let wordQuestions = questions[RemoteQuizQuestionService.normalizeWordKey(word.text)] {
                        fetched[word.id] = wordQuestions
                    }
                }
            }
        } catch {
            loadErrorMessage = error.localizedDescription
            isLoading = false
            return
        }

        questionsByWordID = fetched
        let ready = candidates.filter { fetched[$0.id] != nil }
        skippedWordCount = candidates.count - ready.count

        // 問題が無かった単語（過去の生成失敗・機能追加前の登録語）はサーバ生成をトリガしておく。
        // 生成には時間がかかるため今回は出題せず、次回セッションから出題可能になる
        for word in candidates where fetched[word.id] == nil {
            let text = word.text
            let language = targetLanguage(for: word)
            Task.detached {
                try? await RemoteQuizQuestionService().triggerGeneration(word: text, targetLanguage: language)
            }
        }

        mainQueue = ready
        isLoading = false
        advance()
    }

    /// 次の問題を用意する（キューが尽きたらサマリーへ）
    private func advance() {
        speechService.stop()
        ttsPlayback.stop()
        if current != nil {
            completedCount += 1
        }
        feedback = nil
        selectedChoiceIndex = nil
        typedAnswer = ""
        current = nil

        while true {
            let isRetry: Bool
            let word: Word
            if !mainQueue.isEmpty {
                word = mainQueue.removeFirst()
                isRetry = false
            } else if !retryQueue.isEmpty {
                word = retryQueue.removeFirst()
                isRetry = true
            } else {
                isFinished = true
                return
            }

            // 取得済みの問題から比率調整で形式を選び、バリエーションをランダムに1問引く
            guard let question = pickQuestion(for: word) else { continue }
            sessionCounts[question.format, default: 0] += 1
            current = CurrentQuestion(word: word, question: question, isRetry: isRetry)

            // 音声出題は表示と同時に1回自動再生する
            if let audioText = question.audioText {
                playAudio(audioText)
            }
            return
        }
    }

    /// サーバ保存問題からの出題選択:
    /// 形式は FormatSelector の比率調整で選び、同形式の複数バリエーションからランダムに1件。
    private func pickQuestion(for word: Word) -> ReviewQuestion? {
        guard let questions = questionsByWordID[word.id], !questions.isEmpty else { return nil }
        let available = Set(questions.map(\.format))
        guard let format = FormatSelector.select(
            availableFormats: available, sessionCounts: sessionCounts
        ) else { return nil }
        return questions.filter { $0.format == format }.randomElement()
    }

    // MARK: - 解答処理

    private func submitChoice(_ index: Int, correctIndex: Int, correctAnswer: String) {
        guard feedback == nil else { return }
        selectedChoiceIndex = index
        recordAnswer(isCorrect: index == correctIndex, correctAnswer: correctAnswer)
    }

    private func submitTypedAnswer(_ item: CurrentQuestion) {
        guard feedback == nil, case .typing(let spec) = item.question.answer else { return }
        isAnswerFieldFocused = false
        recordAnswer(
            isCorrect: ReviewAnswerJudge.isCorrect(input: typedAnswer, spec: spec),
            correctAnswer: spec.acceptedAnswers.first ?? item.word.text
        )
    }

    private func recordAnswer(isCorrect: Bool, correctAnswer: String) {
        guard let item = current else { return }
        speechService.stop()
        ttsPlayback.stop()

        // reviewState への反映は初回解答のみ。再出題（retry）は表示だけ
        if !item.isRetry {
            item.word.reviewState = ReviewScheduler.reviewed(item.word.reviewState, isCorrect: isCorrect)
            modelContext.saveOrLog()
            firstAnswerCount += 1
            if isCorrect {
                firstCorrectCount += 1
            } else {
                retryQueue.append(item.word)
            }
        }
        feedback = Feedback(isCorrect: isCorrect, correctAnswer: correctAnswer)
    }

    // MARK: - 音声・イラスト

    /// 生成済みのサーバTTSがあればそれを再生し、無ければ端末内蔵TTSへフォールバックする
    /// （出題テンポを保つため、この画面ではサーバ生成を待たない）
    private func playAudio(_ text: String) {
        let serverModel = ttsModel == "local" ? AppSettingsKeys.fallbackServerTTSModel : ttsModel
        if let url = TTSAudioStore.localURL(text: text, voice: ttsVoice, model: serverModel) {
            ttsPlayback.play(url: url)
        } else {
            speechService.speak(text)
        }
    }

    private func illustrationImage(for wordText: String) -> UIImage? {
        guard let word = allWords.first(where: { $0.text == wordText }),
              let url = illustrationURL(for: word) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    private func illustrationURL(for word: Word) -> URL? {
        WordIllustrationStore.localURL(word: word.text, targetLanguage: targetLanguage(for: word))
    }

    /// イラストのキャッシュキーはAI情報を生成した言語に揃える（WordDetailView と同じ解決順）
    private func targetLanguage(for word: Word) -> String {
        word.aiInfoLanguage
            ?? UserDefaults.standard.string(forKey: AppSettingsKeys.targetLanguageCode)
            ?? AppSettingsKeys.defaultTargetLanguageCode
    }
}

#Preview {
    ReviewSessionView(dueWords: [])
        .modelContainer(for: [Class.self, Lesson.self, Photo.self, Word.self, WordOccurrence.self], inMemory: true)
}
