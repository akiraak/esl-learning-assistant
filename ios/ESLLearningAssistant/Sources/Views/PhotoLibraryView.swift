import SwiftUI
import SwiftData

/// Content タブの Photos セグメント。全レッスンの写真（Photo）を横断して撮影日の新しい順に一覧する。
/// 行タップで詳細へ遷移し、詳細で OCR/翻訳・再翻訳・削除を行う。音声の `AudioLibraryView` の写真版。
/// `ContentTabView` の NavigationStack 配下に埋め込む前提（自前の NavigationStack は持たない）。
/// Photo はレッスン必須（to-one）のため、「+」の追加は `CaptureView` 内のレッスン選択を経由する。
struct PhotoLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Photo.capturedAt, order: .reverse) private var photos: [Photo]

    @State private var isShowingCapture = false
    /// 詳細へ push 中の写真（行タップで設定 → navigationDestination で遷移）
    @State private var selectedPhoto: Photo?
    /// 削除確認ダイアログの対象写真（確認後に実削除する）
    @State private var photoPendingDeletion: Photo?

    private let ocrTranslationService: OCRTranslationService = RemoteOCRTranslationService()

    var body: some View {
        Group {
            if photos.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(photos) { photo in
                        Button {
                            selectedPhoto = photo
                        } label: {
                            PhotoRow(photo: photo, showsLesson: true)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                photoPendingDeletion = photo
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .navigationDestination(item: $selectedPhoto) { photo in
                    PhotoDetailView(photo: photo)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingCapture = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add Photo")
                .accessibilityIdentifier("photoAddButton")
            }
        }
        .sheet(isPresented: $isShowingCapture) {
            // レッスンはシート内の Picker で選ぶ。写真は pending 登録済みで返るので、
            // OCR/翻訳はこの一覧側でバックグラウンド実行する（LessonsView と同じ方式）
            CaptureView { lesson in
                Task { await translatePending(in: lesson) }
            }
        }
        .confirmationDialog(
            "Delete this photo?",
            isPresented: photoDeletionConfirmationBinding,
            titleVisibility: .visible,
            presenting: photoPendingDeletion
        ) { photo in
            Button("Delete", role: .destructive) {
                modelContext.deletePhoto(photo)
                photoPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) {
                photoPendingDeletion = nil
            }
        } message: { _ in
            Text("This will remove the photo and its OCR & translation. This cannot be undone.")
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No photos yet", systemImage: "photo")
        } description: {
            Text("Capture a textbook page, or choose photos from your library.")
        } actions: {
            Button("Add Photo") { isShowingCapture = true }
                .buttonStyle(.borderedProminent)
        }
    }

    private var photoDeletionConfirmationBinding: Binding<Bool> {
        Binding(get: { photoPendingDeletion != nil }, set: { if !$0 { photoPendingDeletion = nil } })
    }

    /// 取り込み直後の未処理写真を順に OCR/翻訳する。処理状態は行のバッジに反映される。
    private func translatePending(in lesson: Lesson) async {
        let targets = lesson.photos.filter { $0.processingStatus == .pending }
        for photo in targets {
            await ocrTranslationService.process(photo)
        }
    }
}

/// 写真 1 行。サムネイル＋タイトル（OCR見出し）＋撮影日＋処理状態。
/// `LessonsView` と `PhotoLibraryView` で共用する（`showsLesson` で紐付くレッスン名を追加表示）。
struct PhotoRow: View {
    let photo: Photo
    /// 紐付くレッスン名（クラス / レッスン）をサブタイトル表示するか（横断一覧用）
    var showsLesson = false

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
            VStack(alignment: .leading, spacing: 2) {
                Text(displayTitle)
                    .lineLimit(1)
                if showsLesson {
                    Text("\(photo.lesson.schoolClass.name) / \(photo.lesson.displayTitle)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    Text(photo.capturedAt, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    statusLabel
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.forward")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .animation(.snappy(duration: 0.25), value: photo.processingStatus)
    }

    /// OCR先頭の見出しを項目名にする。取れない場合は "Untitled"。
    private var displayTitle: String {
        let title = photo.contentTitle
        return title.isEmpty ? "Untitled" : title
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let image = PhotoStorage.loadImage(fileName: photo.imageFileName) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(.secondary.opacity(0.2))
                .frame(width: 44, height: 44)
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch photo.processingStatus {
        case .pending:
            // 順番待ち。穏やかに明滅させて「これから処理される」ことを示す
            Label("Pending", systemImage: "clock")
                .font(.caption)
                .foregroundStyle(.secondary)
                .pulse()
        case .processing:
            // 処理中はインラインスピナー + 明滅テキストで動きを見せる
            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.mini)
                Text("Processing")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .pulse()
        case .completed:
            Label("Done", systemImage: "checkmark.circle")
                .font(.caption)
                .foregroundStyle(.green)
        case .failed:
            Label("Failed", systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }
}
