import SwiftUI
import PhotosUI
import SwiftData

struct CaptureView: View {
    let lesson: Lesson
    var onCaptured: (Photo) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var photosPickerItem: PhotosPickerItem?
    @State private var isShowingCamera = false
    @State private var isProcessing = false

    private let ocrTranslationService: OCRTranslationService = RemoteOCRTranslationService()

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "camera")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("教科書ページを撮影、または写真を選択してください")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button {
                        isShowingCamera = true
                    } label: {
                        Label("カメラで撮影", systemImage: "camera")
                    }
                    .buttonStyle(.borderedProminent)
                }

                PhotosPicker(selection: $photosPickerItem, matching: .images) {
                    Label("写真を選択", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(.bordered)

                if isProcessing {
                    ProgressView("OCR・翻訳を処理中…")
                }
            }
            .padding()
            .navigationTitle("撮影")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .disabled(isProcessing)
            .onChange(of: photosPickerItem) { _, newValue in
                guard let newValue else { return }
                Task { await handlePickedItem(newValue) }
            }
            .fullScreenCover(isPresented: $isShowingCamera) {
                CameraPicker { image in
                    isShowingCamera = false
                    guard let image else { return }
                    Task { await handleCapturedImage(image) }
                }
                .ignoresSafeArea()
            }
        }
    }

    private func handlePickedItem(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        await handleCapturedImage(image)
    }

    private func handleCapturedImage(_ image: UIImage) async {
        guard let fileName = PhotoStorage.save(image) else { return }
        isProcessing = true
        let photo = Photo(lesson: lesson, imageFileName: fileName)
        modelContext.insert(photo)
        await ocrTranslationService.process(photo)
        isProcessing = false
        onCaptured(photo)
        dismiss()
    }
}
