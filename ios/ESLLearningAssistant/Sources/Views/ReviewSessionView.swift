import SwiftUI
import SwiftData

/// 復習クイズのセッション画面。1問ずつ出題 → 回答 → 正誤フィードバック → 次へ。
/// 習熟度方式（docs/plans/archive/review-mastery-progress.md）: 対象は due 単語の先頭5語・最大10問。
/// 未クリア単語のキューをラウンドロビンで回して同じ単語が連続しないようにし、
/// 解答のたびに reviewState を更新する（正解+20% / 不正解−20%、100%でクリア）。
/// 全対象が100%に達したら10問未満でも終了する。
///
/// 問題はサーバ保存のもののみを使う（docs/plans/archive/quiz-questions-server-storage.md）。
/// セッション開始時に /api/quiz-questions/query でまとめて取得し、対象単語の全問題の音声を
/// 一括ダウンロードして始める（進捗バー表示。出題が動的に決まるため事前確定はしない）。
/// サーバに問題が無い単語は出題せずスキップする。
struct ReviewSessionView: View {
    /// 今日の復習対象（呼び出し側で ReviewScheduler.isDue フィルタ済み）
    let dueWords: [Word]

    /// 1セッションの対象単語数上限
    static let sessionWordLimit = 5
    /// 1セッションの出題数上限
    static let sessionQuestionLimit = 10

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    // イラスト4択の誤答単語など、出題対象外の単語のイラスト・言語解決に使う
    @Query private var allWords: [Word]

    @StateObject private var speechService = SpeechService()
    @StateObject private var ttsPlayback = TTSPlaybackService()
    /// 正誤フィードバックの効果音・ハプティック（TTS 再生とは独立した短時間再生）
    @State private var soundEffects = SoundEffectService()

    @State private var hasStarted = false
    @State private var isLoading = true
    @State private var loadErrorMessage: String?
    @State private var questionsByWordID: [UUID: [ReviewQuestion]] = [:]
    /// サーバに問題が無くスキップした due 単語の数（サマリーで知らせる）
    @State private var skippedWordCount = 0
    /// 音声一括ダウンロード中の進捗（nil なら非表示）
    @State private var audioDownload: AudioDownloadProgress?
    /// 問題取得〜音声DLを行う Task。Close・画面破棄でキャンセルする
    @State private var sessionTask: Task<Void, Never>?
    /// 未クリア（習熟度100%未満）単語のラウンドロビンキュー。解答後も未クリアなら末尾へ戻す
    @State private var wordQueue: [Word] = []
    @State private var current: CurrentQuestion?
    @State private var sessionCounts: [ReviewQuestionFormat: Int] = [:]
    /// 解答済みの問題数（進捗表示・出題上限の判定用）
    @State private var completedCount = 0
    /// 解答数と正解数（サマリー表示用）
    @State private var answerCount = 0
    @State private var correctAnswerCount = 0
    /// このセッションで習熟度100%に達した（クリアした）単語数
    @State private var clearedWordCount = 0
    @State private var typedAnswer = ""
    @State private var selectedChoiceIndex: Int?
    @State private var feedback: Feedback?
    @State private var isFinished = false
    @FocusState private var isAnswerFieldFocused: Bool

    private struct AudioDownloadProgress {
        var completed: Int
        var total: Int
    }

    private struct CurrentQuestion {
        var word: Word
        var question: ReviewQuestion
    }

    private struct Feedback {
        var isCorrect: Bool
        var correctAnswer: String
        /// 解答反映後の習熟度（クリア時は100として表示する）
        var masteryPercent: Int
        var isCleared: Bool
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    loadingView
                } else if let audioDownload {
                    downloadingView(audioDownload)
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
            // 出題・フィードバック中の英文の単語タップ→登録/詳細遷移（回答ボタンは対象外）
            .wordTapRegistration()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                    .accessibilityIdentifier("reviewCloseButton")
                }
                // ナビタイトルも単語タップ可能にする
                ToolbarItem(placement: .principal) {
                    TappableEnglishText(text: "Review")
                        .font(.headline)
                }
            }
        }
        .interactiveDismissDisabled()
        .onAppear(perform: startSession)
        .onDisappear {
            sessionTask?.cancel()
            speechService.stop()
            ttsPlayback.stop()
        }
    }

    // MARK: - ローディング・取得失敗

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            TappableEnglishText(text: "Loading questions…", color: .secondary)
                .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("reviewLoadingLabel")
    }

    /// 音声一括ダウンロード中の進捗バー。対象0件ならこの画面は出ない
    private func downloadingView(_ progress: AudioDownloadProgress) -> some View {
        VStack(spacing: 12) {
            ProgressView(value: Double(progress.completed), total: Double(max(progress.total, 1)))
                .frame(maxWidth: 240)
            TappableEnglishText(text: "Preparing audio… \(progress.completed)/\(progress.total)", color: .secondary)
                .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("reviewAudioDownloadLabel")
    }

    private func loadFailedView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            TappableEnglishText(text: "Couldn't Load Questions")
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
                sessionTask = Task { await loadQuestions() }
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
                    debugIdentityBadge(item)

                    TappableEnglishText(text: item.question.instruction)
                        .font(.headline)

                    if let audioText = item.question.audioText {
                        audioReplayButton(audioText)
                        // 解答後は読み上げられた英文を表示し、聞き取れなかった内容を目で確認できるようにする
                        if feedback != nil {
                            audioScript(audioText)
                        }
                    }

                    if let illustrationWord = item.question.promptIllustrationWord {
                        promptIllustration(illustrationWord)
                    }

                    if let displayText = item.question.displayText {
                        // 英語定義・空所つき例文などの英文。単語タップで登録できる（母語表示の問題では
                        // 英単語が無いのでリンク化されない）
                        TappableEnglishText(text: displayText)
                            .font(.title3)
                            .fontWeight(.medium)
                    }

                    answerArea(item)

                    if feedback == nil {
                        dontKnowButton(item)
                    }

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

    /// バグ調査用の識別キャプション。単語 text ＋ 出題形式コード（例: `run · tc7`）を出す。
    /// この2つでサーバ保存問題（quiz_questions: 単語 text ＋ format キー）を直接引ける。
    /// 単語タップ登録の対象にしないため plain Text を使う（誤登録・答えのリンク化を避ける）。
    private func debugIdentityBadge(_ item: CurrentQuestion) -> some View {
        Label("\(item.word.text) · \(item.question.format.rawValue)", systemImage: "ant.fill")
            .font(.caption2.monospaced())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(.secondarySystemBackground), in: Capsule())
            .accessibilityIdentifier("reviewDebugIdentity")
    }

    private var progressHeader: some View {
        // 全単語クリアで早期終了することがあるため、分母は出題上限の10で固定表示する
        let total = Self.sessionQuestionLimit
        return VStack(spacing: 4) {
            ProgressView(value: Double(completedCount), total: Double(total))
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

    /// 解答後に表示する、読み上げられた英文（聞き取り確認用）。単語タップ登録に対応する
    private func audioScript(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Script", systemImage: "text.quote")
                .font(.caption)
                .foregroundStyle(.secondary)
            TappableEnglishText(text: text)
                .font(.title3)
                .fontWeight(.medium)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityIdentifier("reviewAudioScript")
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
                    HStack(spacing: 8) {
                        Text(option)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        // 正誤を色だけに頼らず形でも示す（正解=チェック / 選んだ誤答=バツ）
                        if let icon = choiceResultIcon(index: index, correctIndex: correctIndex) {
                            Image(systemName: icon.name)
                                .font(.title3)
                                .foregroundStyle(icon.color)
                        }
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 14)
                    .background(choiceBackground(index: index, correctIndex: correctIndex), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(
                                choiceBorderColor(index: index, correctIndex: correctIndex),
                                lineWidth: choiceResultIcon(index: index, correctIndex: correctIndex) != nil ? 2.5 : 1
                            )
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
                                illustrationBorderColor(index: index, correctIndex: correctIndex),
                                lineWidth: choiceResultIcon(index: index, correctIndex: correctIndex) != nil ? 3 : 1
                            )
                    )
                    // 右上の正誤バッジ（イラストは背景の色被りで塗りが見分けにくいため形でも示す）
                    .overlay(alignment: .topTrailing) {
                        if let icon = choiceResultIcon(index: index, correctIndex: correctIndex) {
                            Image(systemName: icon.name)
                                .font(.title2)
                                .foregroundStyle(.white, icon.color)
                                .padding(6)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(feedback != nil)
                .accessibilityIdentifier("reviewChoiceButton\(index)")
            }
        }
    }

    /// 回答後は正答を緑・選んだ誤答を赤で塗って見せる
    /// （淡すぎて見分けにくいという報告があったため 0.25 → 0.4 に強調。枠線・アイコンでも補強する）
    private func choiceBackground(index: Int, correctIndex: Int) -> Color {
        guard feedback != nil else { return Color(.secondarySystemBackground) }
        if index == correctIndex { return .green.opacity(0.4) }
        if index == selectedChoiceIndex { return .red.opacity(0.4) }
        return Color(.secondarySystemBackground)
    }

    /// 回答後の正誤アイコン（正解=チェック / 選んだ誤答=バツ）。回答前・対象外の選択肢は nil
    private func choiceResultIcon(index: Int, correctIndex: Int) -> (name: String, color: Color)? {
        guard feedback != nil else { return nil }
        if index == correctIndex { return ("checkmark.circle.fill", .green) }
        if index == selectedChoiceIndex { return ("xmark.circle.fill", .red) }
        return nil
    }

    /// 回答後の選択肢の枠線。正解=緑 / 選んだ誤答=赤 / それ以外は従来の淡い枠線
    private func choiceBorderColor(index: Int, correctIndex: Int) -> AnyShapeStyle {
        guard let icon = choiceResultIcon(index: index, correctIndex: correctIndex) else {
            return AnyShapeStyle(.quaternary)
        }
        return AnyShapeStyle(icon.color)
    }

    /// イラスト4択の枠線（テキスト4択と同じ強調ルール。既定色のみセパレータ）
    private func illustrationBorderColor(index: Int, correctIndex: Int) -> Color {
        choiceResultIcon(index: index, correctIndex: correctIndex)?.color ?? Color(.separator)
    }

    @ViewBuilder
    private func typingArea(_ item: CurrentQuestion) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Type your answer", systemImage: "keyboard")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Image(systemName: "pencil.line")
                    .font(.title3)
                    .foregroundStyle(feedback == nil ? Color.accentColor : .secondary)

                TextField("Enter the word…", text: $typedAnswer)
                    .font(.title3)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .focused($isAnswerFieldFocused)
                    .disabled(feedback != nil)
                    .onSubmit { submitTypedAnswer(item) }
                    .accessibilityIdentifier("reviewTypedAnswerField")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isAnswerFieldFocused ? Color.accentColor : Color.clear, lineWidth: 2)
            )

            if feedback == nil {
                Button {
                    submitTypedAnswer(item)
                } label: {
                    Text("Answer")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(typedAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("reviewSubmitButton")
            }
        }
    }

    /// 分からないときは誤答扱いで正解を提示する（全出題形式で共通）
    private func dontKnowButton(_ item: CurrentQuestion) -> some View {
        Button {
            submitDontKnow(item)
        } label: {
            Text("I don't know")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .tint(.secondary)
        .accessibilityIdentifier("reviewDontKnowButton")
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
                TappableEnglishText(text: "Answer: \(feedback.correctAnswer)")
                    .fontWeight(.medium)
            }

            // この単語の習熟度。100%（クリア）は次回復習日に進んだことを示す
            HStack(spacing: 8) {
                TappableEnglishText(text: "Mastery", color: .secondary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ProgressView(value: Double(feedback.masteryPercent), total: 100)
                Text("\(feedback.masteryPercent)%")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(feedback.isCleared ? .green : .secondary)
                if feedback.isCleared {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
            .accessibilityIdentifier("reviewMasteryRow")

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
                    TappableEnglishText(text: example.english)
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
            Text(
                wordQueue.isEmpty || completedCount + 1 >= Self.sessionQuestionLimit
                    ? "Finish" : "Next"
            )
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
        if answerCount == 0 && skippedWordCount > 0 {
            // 全単語がスキップ（問題未生成）だった場合。自己修復トリガ済みなので時間を置けば出題できる
            VStack(spacing: 16) {
                Image(systemName: "hourglass")
                    .font(.system(size: 56))
                    .foregroundStyle(.secondary)
                TappableEnglishText(text: "Preparing Questions")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("reviewPreparingLabel")
                TappableEnglishText(text: "Questions for today's words are being generated on the server. Please try again in a moment.", color: .secondary)
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
                TappableEnglishText(text: "Session Complete")
                    .font(.title2)
                    .fontWeight(.semibold)
                if answerCount > 0 {
                    TappableEnglishText(text: "\(correctAnswerCount) of \(answerCount) correct", color: .secondary)
                        .foregroundStyle(.secondary)
                    if clearedWordCount > 0 {
                        TappableEnglishText(text: "\(clearedWordCount) word\(clearedWordCount == 1 ? "" : "s") mastered 🎉", color: .secondary)
                            .foregroundStyle(.secondary)
                    }
                }
                if skippedWordCount > 0 {
                    TappableEnglishText(text: "\(skippedWordCount) word\(skippedWordCount == 1 ? "" : "s") skipped (questions being prepared)", color: .secondary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                // 未クリアの単語は due に残るため、続けてセッションを開始できることを知らせる
                let remainingDue = dueWords.filter { ReviewScheduler.isDue($0.reviewState) }.count
                if remainingDue > 0 {
                    TappableEnglishText(text: "\(remainingDue) word\(remainingDue == 1 ? "" : "s") still due today. Start again to continue.", color: .secondary)
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
        sessionTask = Task { await loadQuestions() }
    }

    /// セッション対象（上限5語）の問題をサーバからまとめて取得する。
    /// 問題が無い単語はスキップし、サーバ生成の自己修復トリガだけ投げておく。
    private func loadQuestions() async {
        let candidates = Array(dueWords.prefix(Self.sessionWordLimit))
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

        // 出題は解答結果に応じて動的に決まるため、対象単語の全問題の音声を先に一括ダウンロード
        // する（対象は最大5語なので件数は小さい。docs/plans/archive/review-mastery-progress.md）
        let missingAudioTexts = Array(
            Set(ready.flatMap { (fetched[$0.id] ?? []).compactMap(\.audioText) })
        ).filter { TTSAudioStore.localURL(text: $0, model: AppSettingsKeys.quizTTSModel) == nil }

        var failedTexts: Set<String> = []
        if !missingAudioTexts.isEmpty {
            isLoading = false
            audioDownload = AudioDownloadProgress(completed: 0, total: missingAudioTexts.count)
            failedTexts = await QuizAudioDownloader.download(texts: missingAudioTexts) { completed, total in
                audioDownload = AudioDownloadProgress(completed: completed, total: total)
            }
            // Close で中断された場合は開始しない（画面はすでに閉じている）
            if Task.isCancelled { return }
            audioDownload = nil
        }

        // DL失敗した音声の問題は出題候補から外す
        // （非音声形式はどの単語にもあるため、サーバ不達でも通常は続行できる）
        var usable: [UUID: [ReviewQuestion]] = [:]
        for word in ready {
            let questions = (fetched[word.id] ?? []).filter { question in
                guard let text = question.audioText else { return true }
                return !failedTexts.contains(text)
            }
            if !questions.isEmpty {
                usable[word.id] = questions
            }
        }
        questionsByWordID = usable
        wordQueue = ready.filter { usable[$0.id] != nil }
        // 出題できる問題が残らなかった単語もスキップ扱いで知らせる
        skippedWordCount += ready.count - wordQueue.count
        isLoading = false
        advance()
    }

    /// 次の問題を用意する（10問上限・全単語クリア・出題可能な単語なしでサマリーへ）
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

        while completedCount < Self.sessionQuestionLimit, !wordQueue.isEmpty {
            let word = wordQueue.removeFirst()
            guard let question = pickQuestion(for: word) else { continue }
            sessionCounts[question.format, default: 0] += 1
            current = CurrentQuestion(word: word, question: question)

            // 音声出題は自動再生しない。ユーザーが「Play Audio」ボタンを押したときのみ再生する。
            // テキスト入力形式はキーボードをすぐ出せるよう自動でフォーカスを当てる。
            // TextField の描画完了を待つため、わずかに遅延させてからフォーカスする。
            if case .typing = question.answer {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    isAnswerFieldFocused = true
                }
            }
            return
        }
        isFinished = true
    }

    /// 出題選択。形式は比率調整で選ぶ。追加ダウンロードはしないため、
    /// 音声形式はローカルに音声がある問題に限定する（途中削除への保険）。
    private func pickQuestion(for word: Word) -> ReviewQuestion? {
        let candidates = (questionsByWordID[word.id] ?? []).filter { question in
            guard let text = question.audioText else { return true }
            return TTSAudioStore.localURL(text: text, model: AppSettingsKeys.quizTTSModel) != nil
        }
        return ReviewSessionPlanner.pick(from: candidates, sessionCounts: sessionCounts)
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

    /// 「分からない」= 誤答扱い。選択肢は選ばせないので赤ハイライトは出ず、正解のみ提示する
    private func submitDontKnow(_ item: CurrentQuestion) {
        guard feedback == nil else { return }
        isAnswerFieldFocused = false
        recordAnswer(isCorrect: false, correctAnswer: correctAnswer(for: item))
    }

    /// 出題形式ごとの正解文字列
    private func correctAnswer(for item: CurrentQuestion) -> String {
        switch item.question.answer {
        case .choices(let options, let correctIndex),
             .illustrationChoices(let options, let correctIndex):
            return options[correctIndex]
        case .typing(let spec):
            return spec.acceptedAnswers.first ?? item.word.text
        }
    }

    private func recordAnswer(isCorrect: Bool, correctAnswer: String) {
        guard let item = current else { return }
        speechService.stop()
        ttsPlayback.stop()
        // 正解=気持ちいい音／不正解=それとない音＋ハプティック
        soundEffects.playAnswerFeedback(isCorrect: isCorrect)

        // 解答のたびに反映する（正解+20% / 不正解−20%、100%でクリア）
        let newState = ReviewScheduler.answered(item.word.reviewState, isCorrect: isCorrect)
        item.word.reviewState = newState
        modelContext.saveOrLog()
        answerCount += 1
        if isCorrect {
            correctAnswerCount += 1
        }

        // クリア（dueDate が前進して今日の対象から外れた）なら再出題しない。
        // 未クリアならキュー末尾へ戻す（他の単語が残っていれば連続出題にならない）
        let isCleared = !ReviewScheduler.isDue(newState)
        if isCleared {
            clearedWordCount += 1
        } else {
            wordQueue.append(item.word)
        }
        // 読み上げ英文・フィードバック欄の出現と選択肢の色変化を同じ更新でアニメーションさせると、
        // 色が変わる選択肢（正答/選んだ誤答）だけ移動が遅れて見えるため、この反映は瞬時に行う
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            feedback = Feedback(
                isCorrect: isCorrect,
                correctAnswer: correctAnswer,
                masteryPercent: isCleared ? 100 : newState.masteryPercent,
                isCleared: isCleared
            )
        }
    }

    // MARK: - 音声・イラスト

    /// 出題音声はセッション開始時に一括ダウンロード済みのため、通常はローカルWAVを再生する。
    /// フィードバック欄の単語読み上げなどDL対象外のテキストや、差し替え後に消えた
    /// ファイルに備えて、端末内蔵TTSフォールバックを最終安全網として残す。
    /// モデルはサーバのプリ合成と揃えて flash31 固定（ユーザー設定 ttsModel は使わない）。
    private func playAudio(_ text: String) {
        if let url = TTSAudioStore.localURL(text: text, model: AppSettingsKeys.quizTTSModel) {
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
        .modelContainer(for: [Class.self, Lesson.self, Photo.self, Word.self, WordOccurrence.self, Composition.self, AudioClip.self, YouTubeLink.self, Document.self], inMemory: true)
}
