import SwiftUI
import PhotosUI
import SwiftData

struct CaptureView: View {
    /// 追加先のレッスン。nil の場合は画面内の Picker で選ぶ（Content タブの Photos セグメント用）。
    /// Photo はレッスン必須（to-one）のため、レッスンが1つも無ければ撮影 UI を出さず案内を表示する。
    let fixedLesson: Lesson?
    /// 写真を pending 登録し終えた通知（引数は追加先レッスン）。OCR/翻訳は呼び出し元がバックグラウンドで進める
    var onCaptured: (Lesson) -> Void

    init(lesson: Lesson? = nil, onCaptured: @escaping (Lesson) -> Void) {
        self.fixedLesson = lesson
        self.onCaptured = onCaptured
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Lesson.createdAt, order: .reverse) private var lessons: [Lesson]

    @State private var photosPickerItems: [PhotosPickerItem] = []
    @State private var isShowingCamera = false
    /// レッスン割当は UUID で選ぶ（@Model の Picker タグはIDで扱うのが安全）。nil = 既定（最新レッスン）
    @State private var selectedLessonID: UUID?

    var body: some View {
        NavigationStack {
            Group {
                if fixedLesson == nil && lessons.isEmpty {
                    noLessonState
                } else {
                    captureContent
                }
            }
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

    private var captureContent: some View {
        VStack(spacing: 24) {
            Image(systemName: "camera")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Take a photo of a textbook page, or choose one from your library")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            // 固定レッスン無しで開いたとき（Photos セグメントの「+」）は追加先をここで選ぶ。
            // Picker(menu) は選択値ラベルの折り返しを制御できないため、Menu で1行省略表示にする。
            if fixedLesson == nil {
                HStack {
                    Text("Lesson")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Menu {
                        ForEach(lessons) { lesson in
                            Button(lessonLabel(lesson)) { selectedLessonID = lesson.id }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(targetLesson.map(lessonLabel) ?? "Select")
                                .lineLimit(1)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.footnote)
                        }
                    }
                    .accessibilityIdentifier("captureLessonPicker")
                }
                .padding(.horizontal, 32)
            }

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
    }

    /// レッスンが1つも無いときの案内（写真はレッスン必須のため追加できない）
    private var noLessonState: some View {
        ContentUnavailableView {
            Label("No lessons yet", systemImage: "book.closed")
        } description: {
            Text("Photos belong to a lesson. Create a class and lesson in the Lessons tab first.")
        }
    }

    /// 追加先レッスン。固定レッスン > メニュー選択 > 最新レッスン の順で決める。
    private var targetLesson: Lesson? {
        if let fixedLesson { return fixedLesson }
        guard let id = selectedLessonID else { return lessons.first }
        return lessons.first { $0.id == id } ?? lessons.first
    }

    private func lessonLabel(_ lesson: Lesson) -> String {
        "\(lesson.schoolClass.name) / \(lesson.title)"
    }

    /// ライブラリから選んだ複数枚を順に読み込み、pending 登録する
    private func handlePickedItems(_ items: [PhotosPickerItem]) async {
        guard let lesson = targetLesson else { return }
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
        onCaptured(lesson)
        dismiss()
    }

    private func handleCapturedImage(_ image: UIImage) async {
        guard let lesson = targetLesson,
              let fileName = PhotoStorage.save(image) else { return }
        // pending 登録だけ行い、OCR/翻訳は呼び出し元でバックグラウンド実行する
        let photo = Photo(lesson: lesson, imageFileName: fileName)
        modelContext.insert(photo)
        modelContext.saveOrLog()
        onCaptured(lesson)
        dismiss()
    }
}
