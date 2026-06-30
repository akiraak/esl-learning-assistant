import SwiftUI

struct PhotoDetailView: View {
    let photo: Photo

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
                    HStack {
                        ProgressView()
                        Text("OCR・翻訳を処理中です…")
                            .foregroundStyle(.secondary)
                    }
                case .failed:
                    Text("OCR・翻訳の処理に失敗しました")
                        .foregroundStyle(.red)
                case .completed:
                    VStack(alignment: .leading, spacing: 8) {
                        Text("OCR結果（英語）")
                            .font(.headline)
                        Text(photo.ocrText ?? "")
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("翻訳")
                            .font(.headline)
                        Text(photo.translatedText ?? "")
                    }
                }
            }
            .padding()
        }
        .navigationTitle("写真詳細")
        .navigationBarTitleDisplayMode(.inline)
    }
}
