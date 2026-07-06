import MarkdownUI
import SwiftUI

struct PhotoDetailView: View {
    let photo: Photo

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var isRetrying = false
    @State private var isConfirmingDelete = false
    /// サーバTTS失敗で端末内蔵TTSへフォールバックしたときに、控えめな告知を数秒だけ表示する
    @State private var isUsingFallbackVoice = false
    @StateObject private var speechService = SpeechService()
    @StateObject private var ttsPlayback = TTSPlaybackService()
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
                            // AI音声（サーバTTS）の生成→キャッシュ→再生。単語詳細と同じ TTSButton を共有。
                            // 生成失敗時は端末内蔵TTSへフォールバックする（onGenerateFailure）。
                            TTSButton(
                                text: plainText(photo.ocrText),
                                playback: ttsPlayback,
                                errorMessage: .constant(nil),
                                onGenerateFailure: { fallBackToOnDeviceVoice(plainText(photo.ocrText)) }
                            )
                        }
                        if isUsingFallbackVoice {
                            Label(
                                "Server voice unavailable — using on-device voice",
                                systemImage: "iphone"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .transition(.opacity)
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

                Divider()
                deleteButton
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
    }

    private func stopSpeaking() {
        speechService.stop()
        ttsPlayback.stop()
    }

    /// サーバTTSが使えないとき、端末内蔵TTSで読み上げつつ控えめな告知を数秒表示する
    private func fallBackToOnDeviceVoice(_ text: String) {
        speechService.speak(text)
        withAnimation(.snappy) { isUsingFallbackVoice = true }
        Task {
            try? await Task.sleep(for: .seconds(5))
            withAnimation(.snappy) { isUsingFallbackVoice = false }
        }
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

    private var deleteButton: some View {
        Button(role: .destructive) {
            isConfirmingDelete = true
        } label: {
            Label("Delete Photo", systemImage: "trash")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(.red)
        .confirmationDialog(
            "Delete this photo?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                modelContext.deletePhoto(photo)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove the photo and its OCR & translation. This cannot be undone.")
        }
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
