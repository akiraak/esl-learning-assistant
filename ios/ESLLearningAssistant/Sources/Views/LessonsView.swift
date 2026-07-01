import SwiftUI
import SwiftData

struct LessonsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Class.createdAt) private var classes: [Class]

    @AppStorage("currentClassID") private var currentClassIDString: String?
    @AppStorage("currentLessonID") private var currentLessonIDString: String?

    @State private var isShowingSwitcher = false
    @State private var isShowingCapture = false
    @State private var selectedPhoto: Photo?
    @State private var isBulkTranslating = false
    @State private var bulkTranslateDone = 0
    @State private var bulkTranslateTotal = 0

    private let ocrTranslationService: OCRTranslationService = RemoteOCRTranslationService()

    var body: some View {
        NavigationStack {
            Group {
                if let schoolClass = currentClass {
                    List {
                        switcherCard(schoolClass)
                        if let lesson = currentLesson {
                            lessonContent(lesson)
                        } else {
                            emptyLessonSection(in: schoolClass)
                        }
                    }
                } else {
                    emptyClassState
                }
            }
            .navigationTitle("レッスン")
            .sheet(isPresented: $isShowingSwitcher) {
                ClassLessonSwitcherView(
                    currentClassID: currentClassIDBinding,
                    currentLessonID: currentLessonIDBinding
                )
            }
            .sheet(isPresented: $isShowingCapture) {
                if let lesson = currentLesson {
                    CaptureView(lesson: lesson) { photo in
                        selectedPhoto = photo
                    }
                }
            }
            .navigationDestination(item: $selectedPhoto) { photo in
                PhotoDetailView(photo: photo)
            }
        }
    }

    // MARK: - 現在のクラス・レッスン

    private var currentClass: Class? {
        if let id = currentClassIDString.flatMap(UUID.init),
           let match = classes.first(where: { $0.id == id }) {
            return match
        }
        return classes.max(by: { $0.createdAt < $1.createdAt })
    }

    private var currentLesson: Lesson? {
        guard let schoolClass = currentClass else { return nil }
        if let id = currentLessonIDString.flatMap(UUID.init),
           let match = schoolClass.lessons.first(where: { $0.id == id }) {
            return match
        }
        return schoolClass.lessons.max(by: { $0.createdAt < $1.createdAt })
    }

    private var currentClassIDBinding: Binding<UUID?> {
        Binding(
            get: { currentClassIDString.flatMap(UUID.init) },
            set: { currentClassIDString = $0?.uuidString }
        )
    }

    private var currentLessonIDBinding: Binding<UUID?> {
        Binding(
            get: { currentLessonIDString.flatMap(UUID.init) },
            set: { currentLessonIDString = $0?.uuidString }
        )
    }

    // MARK: - ヘッダーカード

    private func switcherCard(_ schoolClass: Class) -> some View {
        Section {
            Button {
                isShowingSwitcher = true
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(schoolClass.name)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(currentLesson?.title ?? "レッスン未選択")
                            .font(.title3)
                            .fontWeight(.semibold)
                    }
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("classLessonSwitcherButton")
        }
    }

    // MARK: - コンテンツ

    @ViewBuilder
    private func lessonContent(_ lesson: Lesson) -> some View {
        Section {
            Button {
                isShowingCapture = true
            } label: {
                Label("写真を追加", systemImage: "camera")
            }
        }

        Section("コンテンツ (\(lesson.photos.count))") {
            let photos = lesson.photos.sorted { $0.capturedAt > $1.capturedAt }
            let untranslatedCount = photos.filter { $0.processingStatus == .pending || $0.processingStatus == .failed }.count
            if photos.isEmpty {
                Text("まだコンテンツがありません")
                    .foregroundStyle(.secondary)
            } else {
                if untranslatedCount > 0 {
                    Button {
                        Task { await translateAllPending(in: lesson) }
                    } label: {
                        if isBulkTranslating {
                            HStack {
                                ProgressView()
                                Text("翻訳中… (\(bulkTranslateDone)/\(bulkTranslateTotal))")
                            }
                        } else {
                            Label("未翻訳の写真をまとめて翻訳 (\(untranslatedCount)件)", systemImage: "translate")
                        }
                    }
                    .disabled(isBulkTranslating)
                }
                ForEach(photos) { photo in
                    Button {
                        selectedPhoto = photo
                    } label: {
                        PhotoRow(photo: photo)
                    }
                    .buttonStyle(.plain)
                }
            }
        }

        wordsSection(lesson)

        Section("問題") {
            Text("問題機能は今後実装予定です")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func wordsSection(_ lesson: Lesson) -> some View {
        let words = lessonWords(lesson)
        Section("単語 (\(words.count))") {
            if words.isEmpty {
                Text("まだ単語がありません")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(words) { word in
                    NavigationLink {
                        WordDetailView(word: word)
                    } label: {
                        WordRow(word: word)
                    }
                }
            }
        }
    }

    /// レッスンの出現記録から重複を除いた単語一覧（登録が新しい順）
    private func lessonWords(_ lesson: Lesson) -> [Word] {
        var seen = Set<UUID>()
        return lesson.wordOccurrences
            .sorted { $0.occurredAt > $1.occurredAt }
            .compactMap { occurrence in
                guard seen.insert(occurrence.word.id).inserted else { return nil }
                return occurrence.word
            }
    }

    // MARK: - 空状態

    private var emptyClassState: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.3")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("クラスがありません")
                .font(.title2)
                .fontWeight(.semibold)
            Text("受講しているクラスを追加して始めましょう。")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                isShowingSwitcher = true
            } label: {
                Label("クラスを追加", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("lessonAddClassButton")
        }
    }

    private func emptyLessonSection(in schoolClass: Class) -> some View {
        Section {
            VStack(spacing: 12) {
                Image(systemName: "book.closed")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text("レッスンがありません")
                    .font(.headline)
                Text("\(schoolClass.name) にレッスンを追加して始めましょう。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button {
                    isShowingSwitcher = true
                } label: {
                    Label("レッスンを追加", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
    }

    // MARK: - アクション

    private func translateAllPending(in lesson: Lesson) async {
        let targets = lesson.photos.filter { $0.processingStatus == .pending || $0.processingStatus == .failed }
        guard !targets.isEmpty else { return }
        isBulkTranslating = true
        bulkTranslateDone = 0
        bulkTranslateTotal = targets.count
        for photo in targets {
            await ocrTranslationService.process(photo)
            bulkTranslateDone += 1
        }
        isBulkTranslating = false
    }
}

private struct PhotoRow: View {
    let photo: Photo

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
            VStack(alignment: .leading, spacing: 2) {
                Text(photo.capturedAt, style: .date)
                statusLabel
            }
            Spacer()
        }
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

    private var statusLabel: some View {
        let (text, systemImage, color): (String, String, Color) = {
            switch photo.processingStatus {
            case .pending: return ("未処理", "clock", .secondary)
            case .processing: return ("処理中", "hourglass", .secondary)
            case .completed: return ("完了", "checkmark.circle", .green)
            case .failed: return ("失敗", "exclamationmark.triangle", .red)
            }
        }()
        return Label(text, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(color)
    }
}

#Preview {
    LessonsView()
        .modelContainer(for: [Class.self, Lesson.self, Photo.self, Word.self, WordOccurrence.self], inMemory: true)
}
