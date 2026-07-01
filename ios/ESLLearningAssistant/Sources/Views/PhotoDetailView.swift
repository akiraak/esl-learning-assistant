import MarkdownUI
import SwiftUI

struct PhotoDetailView: View {
    let photo: Photo

    @State private var isRetrying = false
    @StateObject private var speechService = SpeechService()
    @StateObject private var geminiSpeechService = GeminiSpeechService()
    @AppStorage(AppSettingsKeys.ttsEngine) private var ttsEngine = AppSettingsKeys.defaultTTSEngine
    @AppStorage(AppSettingsKeys.ttsVoice) private var ttsVoice = AppSettingsKeys.defaultTTSVoice
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
                case .pending:
                    HStack {
                        ProgressView()
                        Text("OCR・翻訳を開始しています…")
                            .foregroundStyle(.secondary)
                    }
                case .processing:
                    VStack(alignment: .leading, spacing: 8) {
                        Text("OCR・翻訳の処理が完了していません（前回中断された可能性があります）")
                            .foregroundStyle(.secondary)
                        retryButton
                    }
                case .failed:
                    VStack(alignment: .leading, spacing: 8) {
                        Text("OCR・翻訳の処理に失敗しました")
                            .foregroundStyle(.red)
                        retryButton
                    }
                case .completed:
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("OCR結果（英語）")
                                .font(.headline)
                            Spacer()
                            speechButton
                        }
                        Markdown(photo.ocrText ?? "")
                            .markdownHeadingHighlight()
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("翻訳")
                            .font(.headline)
                        Markdown(photo.translatedText ?? "")
                            .markdownHeadingHighlight()
                    }
                    Divider()
                    retranslateButton
                }
            }
            .padding()
        }
        .navigationTitle("写真詳細")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: photo.id) {
            stopSpeaking()
            guard photo.processingStatus == .pending else { return }
            await retry()
        }
        .onDisappear {
            stopSpeaking()
        }
    }

    private var isSpeaking: Bool {
        speechService.isSpeaking || geminiSpeechService.isSpeaking
    }

    private func stopSpeaking() {
        speechService.stop()
        geminiSpeechService.stop()
    }

    private var speechButton: some View {
        Button {
            if isSpeaking {
                stopSpeaking()
            } else if ttsEngine == "gemini" {
                geminiSpeechService.speak(plainText(photo.ocrText), voice: ttsVoice, model: ttsModel)
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
                Label("翻訳する", systemImage: "arrow.clockwise")
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
                Label("再翻訳する", systemImage: "arrow.clockwise")
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

private extension View {
    /// OCR結果・翻訳結果の本文中に埋め込まれたMarkdown見出し（`#`〜`###`）を、
    /// 背景色付きのラベルとして表示し、地の文と区別しやすくする。
    func markdownHeadingHighlight() -> some View {
        self
            .markdownBlockStyle(\.heading1) { markdownHeadingLabel($0, fontSize: .em(1.6), opacity: 0.18) }
            .markdownBlockStyle(\.heading2) { markdownHeadingLabel($0, fontSize: .em(1.35), opacity: 0.14) }
            .markdownBlockStyle(\.heading3) { markdownHeadingLabel($0, fontSize: .em(1.15), opacity: 0.1) }
    }
}

@MainActor
@ViewBuilder
private func markdownHeadingLabel(
    _ configuration: BlockConfiguration,
    fontSize: RelativeSize,
    opacity: Double
) -> some View {
    configuration.label
        .markdownTextStyle {
            FontWeight(.bold)
            FontSize(fontSize)
        }
        .relativePadding(.horizontal, length: .em(0.6))
        .relativePadding(.vertical, length: .em(0.3))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(opacity), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .markdownMargin(top: .em(1.2), bottom: .em(0.6))
}
