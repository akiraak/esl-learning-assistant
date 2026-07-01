import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Class.createdAt) private var classes: [Class]

    @AppStorage("currentClassID") private var currentClassIDString: String?
    @AppStorage("currentLessonID") private var currentLessonIDString: String?

    @State private var isShowingSwitcher = false
    @State private var isShowingNewLessonAlert = false
    @State private var newLessonTitle = ""
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
                    if let lesson = currentLesson {
                        lessonContent(lesson)
                    } else {
                        emptyLessonState(in: schoolClass)
                    }
                } else {
                    emptyClassState
                }
            }
            .navigationTitle("ホーム")
            .toolbar {
                if let schoolClass = currentClass {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            isShowingSwitcher = true
                        } label: {
                            Label(schoolClass.name, systemImage: "chevron.down")
                                .labelStyle(.titleAndIcon)
                        }
                    }
                }
            }
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
            .alert("新しいレッスン", isPresented: $isShowingNewLessonAlert) {
                TextField("レッスン名", text: $newLessonTitle)
                Button("追加", action: addLesson)
                Button("キャンセル", role: .cancel) {}
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

    // MARK: - コンテンツ

    @ViewBuilder
    private func lessonContent(_ lesson: Lesson) -> some View {
        List {
            Section {
                Button {
                    newLessonTitle = ""
                    isShowingNewLessonAlert = true
                } label: {
                    Label("新しいレッスン", systemImage: "plus")
                }
            } header: {
                Text(lesson.title)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .textCase(nil)
                    .padding(.bottom, 4)
            }

            Section {
                Button {
                    isShowingCapture = true
                } label: {
                    Label("写真を追加", systemImage: "camera")
                }
            }

            Section("写真 (\(lesson.photos.count))") {
                let photos = lesson.photos.sorted { $0.capturedAt > $1.capturedAt }
                let untranslatedCount = photos.filter { $0.processingStatus == .pending || $0.processingStatus == .failed }.count
                if photos.isEmpty {
                    Text("まだ写真がありません")
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
        }
    }

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
            .accessibilityIdentifier("homeAddClassButton")
        }
    }

    private func emptyLessonState(in schoolClass: Class) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "book.closed")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("レッスンがありません")
                .font(.title2)
                .fontWeight(.semibold)
            Text("\(schoolClass.name) にレッスンを追加して始めましょう。")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                newLessonTitle = ""
                isShowingNewLessonAlert = true
            } label: {
                Label("新しいレッスン", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - アクション

    private func addLesson() {
        guard let schoolClass = currentClass else { return }
        let trimmed = newLessonTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let lesson = Lesson(schoolClass: schoolClass, title: trimmed)
        modelContext.insert(lesson)
        currentClassIDString = schoolClass.id.uuidString
        currentLessonIDString = lesson.id.uuidString
    }

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
    HomeView()
        .modelContainer(for: [Class.self, Lesson.self, Photo.self], inMemory: true)
}
