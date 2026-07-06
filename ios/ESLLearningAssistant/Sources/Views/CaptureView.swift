import SwiftUI
import PhotosUI
import SwiftData

struct CaptureView: View {
    let lesson: Lesson
    /// 写真を pending 登録し終えた通知。OCR/翻訳は呼び出し元がバックグラウンドで進める
    var onCaptured: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var photosPickerItems: [PhotosPickerItem] = []
    @State private var isShowingCamera = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "camera")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("Take a photo of a textbook page, or choose one from your library")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button {
                        isShowingCamera = true
                    } label: {
                        Label("Take Photo", systemImage: "camera")
                    }
                    .buttonStyle(.borderedProminent)
                }

                PhotosPicker(selection: $photosPickerItems, matching: .images) {
                    Label("Choose Photos", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .navigationTitle("Capture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onChange(of: photosPickerItems) { _, newValue in
                guard !newValue.isEmpty else { return }
                Task { await handlePickedItems(newValue) }
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

    /// ライブラリから選んだ複数枚を順に読み込み、pending 登録する
    private func handlePickedItems(_ items: [PhotosPickerItem]) async {
        var didInsert = false
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data),
                  let fileName = PhotoStorage.save(image) else { continue }
            // pending 登録だけ行い、OCR/翻訳は呼び出し元でバックグラウンド実行する
            let photo = Photo(lesson: lesson, imageFileName: fileName)
            modelContext.insert(photo)
            didInsert = true
        }
        guard didInsert else { return }
        modelContext.saveOrLog()
        onCaptured()
        dismiss()
    }

    private func handleCapturedImage(_ image: UIImage) async {
        guard let fileName = PhotoStorage.save(image) else { return }
        // pending 登録だけ行い、OCR/翻訳は呼び出し元でバックグラウンド実行する
        let photo = Photo(lesson: lesson, imageFileName: fileName)
        modelContext.insert(photo)
        modelContext.saveOrLog()
        onCaptured()
        dismiss()
    }
}
