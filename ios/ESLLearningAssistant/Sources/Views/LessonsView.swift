import SwiftUI
import SwiftData

struct LessonsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppRouter.self) private var router
    @Query(sort: \Class.createdAt) private var classes: [Class]

    @AppStorage("currentClassID") private var currentClassIDString: String?
    @AppStorage("currentLessonID") private var currentLessonIDString: String?

    @State private var isShowingSwitcher = false
    @State private var isShowingCapture = false
    @State private var isEditingMemo = false
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
            .navigationDestination(isPresented: $isEditingMemo) {
                if let lesson = currentLesson {
                    LessonMemoEditView(lesson: lesson)
                }
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
                        Text(currentLesson?.title ?? "No lesson selected")
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
            let photos = lesson.photos.sorted { $0.capturedAt > $1.capturedAt }
            let untranslatedCount = photos.filter { $0.processingStatus == .pending || $0.processingStatus == .failed }.count
            if photos.isEmpty {
                Text("No content yet")
                    .foregroundStyle(.secondary)
            } else {
                if untranslatedCount > 0 {
                    Button {
                        Task { await translateAllPending(in: lesson) }
                    } label: {
                        if isBulkTranslating {
                            HStack {
                                ProgressView()
                                Text("Translating… (\(bulkTranslateDone)/\(bulkTranslateTotal))")
                            }
                        } else {
                            Label("Translate Untranslated Photos (\(untranslatedCount))", systemImage: "translate")
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
        } header: {
            HStack {
                Text("Content (\(lesson.photos.count))")
                Spacer()
                Button {
                    isShowingCapture = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityIdentifier("lessonPhotoAddButton")
                .accessibilityLabel("Add Photo")
            }
        }

        wordsSection(lesson)

        memoSection(lesson)

        Section("Questions") {
            Text("Question features are coming soon")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func wordsSection(_ lesson: Lesson) -> some View {
        let words = lessonWords(lesson)
        Section {
            if words.isEmpty {
                Text("No words yet")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(words) { word in
                    // 単語詳細はWordsタブに集約するため、タブを切り替えて表示する
                    Button {
                        router.showWord(word)
                    } label: {
                        HStack {
                            WordRow(word: word)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            HStack {
                Text("Words (\(words.count))")
                Spacer()
                // 単語追加はWordsタブの追加画面に集約し、このレッスンを固定した状態で開く
                Button {
                    router.showAddWord(for: lesson)
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityIdentifier("lessonWordAddButton")
                .accessibilityLabel("Add Word")
            }
        }
    }

    @ViewBuilder
    private func memoSection(_ lesson: Lesson) -> some View {
        Section("Memo") {
            Button {
                isEditingMemo = true
            } label: {
                HStack {
                    if let memo = lesson.memo, !memo.isEmpty {
                        Text(memo)
                    } else {
                        Text("No memo yet")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "square.and.pencil")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("lessonMemoButton")
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
            Text("No Classes")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Add a class you are taking to get started.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                isShowingSwitcher = true
            } label: {
                Label("Add Class", systemImage: "plus")
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
                Text("No Lessons")
                    .font(.headline)
                Text("Add a lesson to \(schoolClass.name) to get started.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button {
                    isShowingSwitcher = true
                } label: {
                    Label("Add Lesson", systemImage: "plus")
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
            case .pending: return ("Pending", "clock", .secondary)
            case .processing: return ("Processing", "hourglass", .secondary)
            case .completed: return ("Done", "checkmark.circle", .green)
            case .failed: return ("Failed", "exclamationmark.triangle", .red)
            }
        }()
        return Label(text, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(color)
    }
}

#Preview {
    LessonsView()
        .environment(AppRouter())
        .modelContainer(for: [Class.self, Lesson.self, Photo.self, Word.self, WordOccurrence.self], inMemory: true)
}
