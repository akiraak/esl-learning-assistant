import SwiftUI
import SwiftData

struct LessonsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Class.createdAt) private var classes: [Class]

    @AppStorage("currentClassID") private var currentClassIDString: String?
    @AppStorage("currentLessonID") private var currentLessonIDString: String?

    @State private var isShowingSwitcher = false
    /// コンテンツ追加の入口（タイプ選択シート）。写真/Audio/YouTube をここから追加する
    @State private var isShowingAddContent = false
    @State private var isEditingMemo = false
    /// レッスン固定の単語追加シートを開く対象。閉じればこのレッスン画面に戻る
    @State private var wordAddLesson: Lesson?
    /// この画面のスタックで詳細を開く単語。戻ればこのレッスン画面に戻る
    @State private var selectedWord: Word?
    @State private var selectedPhoto: Photo?
    /// 削除確認ダイアログの対象写真（確認後に実削除する）
    @State private var photoPendingDeletion: Photo?
    @State private var isBulkTranslating = false
    @State private var bulkTranslateDone = 0
    @State private var bulkTranslateTotal = 0
    @State private var selectedAudioClip: AudioClip?
    /// この画面のスタックで開く文書詳細。戻ればレッスンに戻る
    @State private var selectedDocument: Document?
    /// この画面のスタックで開く YouTube 詳細。戻ればレッスンに戻る
    @State private var selectedYouTubeLink: YouTubeLink?
    /// レッスン画面の音声再生（Audioタブとは独立したプレイヤー）
    @StateObject private var audioPlayback = TTSPlaybackService()

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
            // 画面内の英語UIテキストの単語タップ→登録/詳細遷移
            .wordTapRegistration()
            .sheet(isPresented: $isShowingSwitcher) {
                ClassLessonSwitcherView(
                    currentClassID: currentClassIDBinding,
                    currentLessonID: currentLessonIDBinding
                )
            }
            .sheet(isPresented: $isShowingAddContent) {
                if let lesson = currentLesson {
                    AddContentTypeView(lesson: lesson) {
                        // 写真追加後は詳細へ自動遷移せずレッスン画面に留まり、
                        // OCR/翻訳は永続する LessonsView 側でバックグラウンド実行する
                        Task { await translateAllPending(in: lesson) }
                    }
                }
            }
            .sheet(item: $wordAddLesson) { lesson in
                WordAddView(fixedLesson: lesson)
            }
            .navigationDestination(item: $selectedPhoto) { photo in
                PhotoDetailView(photo: photo)
            }
            .navigationDestination(item: $selectedWord) { word in
                WordDetailView(word: word)
            }
            .navigationDestination(item: $selectedAudioClip) { clip in
                AudioDetailView(clip: clip, playback: audioPlayback)
            }
            .navigationDestination(item: $selectedDocument) { document in
                DocumentDetailView(document: document)
            }
            .navigationDestination(item: $selectedYouTubeLink) { link in
                YouTubeDetailView(link: link)
            }
            .navigationDestination(isPresented: $isEditingMemo) {
                if let lesson = currentLesson {
                    LessonMemoEditView(lesson: lesson)
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
        .onDisappear { audioPlayback.stop() }
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
        // 写真・Audio・YouTube を1つに束ね、追加日時の降順で並べた統合コンテンツ一覧
        let items = lesson.contentItems
        Section {
            let untranslatedCount = lesson.photos.filter { $0.processingStatus == .pending || $0.processingStatus == .failed }.count
            if items.isEmpty {
                TappableEnglishText(text: "No content yet", color: .secondary)
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
                ForEach(items) { item in
                    contentRow(item)
                }
            }
        } header: {
            HStack {
                TappableEnglishText(text: "Content (\(items.count))")
                Spacer()
                Button {
                    isShowingAddContent = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityIdentifier("lessonContentAddButton")
                .accessibilityLabel("Add Content")
            }
        }

        wordsSection(lesson)

        memoSection(lesson)

        Section {
            TappableEnglishText(text: "Question features are coming soon", color: .secondary)
                .foregroundStyle(.secondary)
        } header: {
            TappableEnglishText(text: "Questions")
        }
    }

    /// 統合コンテンツ一覧の1行。種別ごとに行の見た目・タップ先・スワイプ削除を分岐する。
    @ViewBuilder
    private func contentRow(_ item: LessonContentItem) -> some View {
        switch item {
        case .photo(let photo):
            Button {
                selectedPhoto = photo
            } label: {
                PhotoRow(photo: photo)
            }
            .buttonStyle(.plain)
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                    photoPendingDeletion = photo
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        case .audio(let clip):
            // 行タップで詳細へ遷移する（再生は詳細画面で行う。Audioタブと同挙動）
            Button {
                selectedAudioClip = clip
            } label: {
                AudioClipRow(clip: clip)
            }
            .buttonStyle(.plain)
        case .document(let document):
            // 行タップで詳細へ遷移する（原本表示・抽出は詳細画面で行う。Documentsタブと同挙動）
            Button {
                selectedDocument = document
            } label: {
                DocumentRow(document: document)
            }
            .buttonStyle(.plain)
        case .youtube(let link):
            Button {
                selectedYouTubeLink = link
            } label: {
                YouTubeRow(link: link)
            }
            .buttonStyle(.plain)
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                    deleteYouTubeLink(link)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    @ViewBuilder
    private func wordsSection(_ lesson: Lesson) -> some View {
        let words = lessonWords(lesson)
        Section {
            if words.isEmpty {
                TappableEnglishText(text: "No words yet", color: .secondary)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(words) { word in
                    // 詳細はこの画面のスタックにプッシュする（戻ればレッスンに戻る）
                    Button {
                        selectedWord = word
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
                    // レッスンとのリンク（WordOccurrence）を外すのみ。Word本体はWordsタブに残る
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            removeWordFromLesson(word, in: lesson)
                        } label: {
                            Label("Remove", systemImage: "minus.circle")
                        }
                    }
                }
            }
        } header: {
            HStack {
                TappableEnglishText(text: "Words (\(words.count))")
                Spacer()
                // このレッスンを固定した追加シートをこの画面上で開く（閉じればレッスンに戻る）
                Button {
                    wordAddLesson = lesson
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityIdentifier("lessonWordAddButton")
                .accessibilityLabel("Add Word")
            }
        }
    }

    private var photoDeletionConfirmationBinding: Binding<Bool> {
        Binding(get: { photoPendingDeletion != nil }, set: { if !$0 { photoPendingDeletion = nil } })
    }

    /// YouTube リンクを削除する。to-one/cascade（レッスン固有）なので実体の後始末は不要。
    private func deleteYouTubeLink(_ link: YouTubeLink) {
        modelContext.delete(link)
        modelContext.saveOrLog()
    }

    @ViewBuilder
    private func memoSection(_ lesson: Lesson) -> some View {
        Section {
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
        } header: {
            TappableEnglishText(text: "Memo")
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
            TappableEnglishText(text: "No Classes")
                .font(.title2)
                .fontWeight(.semibold)
            TappableEnglishText(text: "Add a class you are taking to get started.", color: .secondary)
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
                TappableEnglishText(text: "No Lessons")
                    .font(.headline)
                TappableEnglishText(text: "Add a lesson to \(schoolClass.name) to get started.", color: .secondary)
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

    /// レッスンとのリンク（WordOccurrence）だけを削除する。Word本体は単語一覧に残す
    private func removeWordFromLesson(_ word: Word, in lesson: Lesson) {
        for occurrence in lesson.wordOccurrences where occurrence.word.id == word.id {
            modelContext.delete(occurrence)
        }
        // autosave任せだと直後にアプリが強制終了された場合に失われるため明示的に保存する
        modelContext.saveOrLog()
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
                Text(displayTitle)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(photo.capturedAt, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    statusLabel
                }
            }
            Spacer()
        }
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

#Preview {
    LessonsView()
        .modelContainer(for: [Class.self, Lesson.self, Photo.self, Word.self, WordOccurrence.self, Composition.self, AudioClip.self, YouTubeLink.self, Document.self], inMemory: true)
}
