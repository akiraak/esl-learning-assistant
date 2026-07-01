import SwiftUI

struct PhotoDetailView: View {
    let photo: Photo

    @State private var isRetrying = false
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
                        Text("OCR結果（英語）")
                            .font(.headline)
                        markdownText(photo.ocrText)
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("翻訳")
                            .font(.headline)
                        markdownText(photo.translatedText)
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
            guard photo.processingStatus == .pending else { return }
            await retry()
        }
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

    private func markdownText(_ value: String?) -> Text {
        guard let value, !value.isEmpty else { return Text("") }
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
        guard let attributed = try? AttributedString(markdown: value, options: options) else {
            return Text(value)
        }
        return Text(attributed)
    }
}
