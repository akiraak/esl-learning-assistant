import MarkdownUI
import SwiftUI

struct PhotoDetailView: View {
    let photo: Photo

    @State private var isRetrying = false
    @StateObject private var speechService = SpeechService()
    @StateObject private var geminiSpeechService = GeminiSpeechService()
    @StateObject private var ttsPlayback = TTSPlaybackService()
    @AppStorage(AppSettingsKeys.ttsModel) private var ttsModel = AppSettingsKeys.defaultTTSModel
    private let ocrTranslationService: OCRTranslationService = RemoteOCRTranslationService()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let image = PhotoStorage.loadImage(fileName: photo.imageFileName) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                switch photo.processingStatus {
                case .pending, .processing:
                    VStack(alignment: .leading, spacing: 16) {
                        PhotoProcessingView()
                        // 稀にアプリ強制終了で processing のまま固まった場合の回復手段（控えめに）
                        retryButton
                    }
                case .failed:
                    VStack(alignment: .leading, spacing: 8) {
                        TappableEnglishText(text: "OCR & translation failed", color: .red)
                            .foregroundStyle(.red)
                        if let errorMessage = photo.processingErrorMessage {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        retryButton
                    }
                case .completed:
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            TappableEnglishText(text: "OCR Result (English)")
                                .font(.headline)
                            Spacer()
                            speechButton
                        }
                        // OCR英文は書式（見出しハイライト等）を保ったまま単語ごとにタップ可能。
                        // タップ→登録は下の .wordTapRegistration が受ける（sourcePhoto でOCR文脈もAI生成へ渡る）
                        TappableMarkdown(markdown: photo.ocrText ?? "")
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        TappableEnglishText(text: "Translation")
                            .font(.headline)
                        Markdown(photo.translatedText ?? "")
                            .markdownHeadingHighlight()
                    }
                    Divider()
                    retranslateButton
                }
            }
            .padding()
            .animation(.snappy(duration: 0.25), value: photo.processingStatus)
        }
        // OCR英文の単語タップ→登録/詳細遷移。出現元の写真とレッスンを紐付け、AI生成にOCR文脈を渡す
        .wordTapRegistration(sourcePhoto: photo, lesson: photo.lesson)
        .navigationTitle("Photo Detail")
        .navigationBarTitleDisplayMode(.inline)
        // ナビタイトルも単語タップ可能にする（principal 項目でタイトル表示を差し替え）
        .toolbar {
            ToolbarItem(placement: .principal) {
                TappableEnglishText(text: "Photo Detail")
                    .font(.headline)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if ttsPlayback.isActive {
                TTSPlayerBar(playback: ttsPlayback)
            }
        }
        .animation(.snappy(duration: 0.2), value: ttsPlayback.isActive)
        .task(id: photo.id) {
            stopSpeaking()
            guard photo.processingStatus == .pending else { return }
            await retry()
        }
        .onDisappear {
            stopSpeaking()
        }
        .alert(
            "Speech Failed",
            isPresented: Binding(
                get: { geminiSpeechService.errorMessage != nil },
                set: { if !$0 { geminiSpeechService.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(geminiSpeechService.errorMessage ?? "")
        }
    }

    private var isSpeaking: Bool {
        speechService.isSpeaking || ttsPlayback.isActive
    }

    private func stopSpeaking() {
        speechService.stop()
        ttsPlayback.stop()
    }

    private var speechButton: some View {
        Button {
            if isSpeaking {
                stopSpeaking()
            } else if ttsModel != "local" {
                geminiSpeechService.speak(plainText(photo.ocrText), model: ttsModel, playback: ttsPlayback)
            } else {
                speechService.speak(plainText(photo.ocrText))
            }
        } label: {
            if geminiSpeechService.isLoading {
                ProgressView()
            } else {
                Image(systemName: isSpeaking ? "stop.fill" : "speaker.wave.2.fill")
            }
        }
        .buttonStyle(.bordered)
        .disabled((photo.ocrText ?? "").isEmpty || geminiSpeechService.isLoading)
    }

    private var retryButton: some View {
        Button {
            Task { await retry() }
        } label: {
            if isRetrying {
                ProgressView()
            } else {
                Label("Translate", systemImage: "arrow.clockwise")
            }
        }
        .buttonStyle(.bordered)
        .disabled(isRetrying)
    }

    private var retranslateButton: some View {
        Button {
            Task { await retry() }
        } label: {
            if isRetrying {
                ProgressView()
            } else {
                Label("Retranslate", systemImage: "arrow.clockwise")
            }
        }
        .buttonStyle(.bordered)
        .disabled(isRetrying)
    }

    private func retry() async {
        isRetrying = true
        await ocrTranslationService.process(photo)
        isRetrying = false
    }

    private func plainText(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "" }
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
        guard let attributed = try? AttributedString(markdown: value, options: options) else {
            return value
        }
        return String(attributed.characters)
    }
}
