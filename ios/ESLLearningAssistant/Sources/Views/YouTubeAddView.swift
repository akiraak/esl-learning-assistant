import SwiftUI
import SwiftData

/// YouTube 動画をレッスンに追加するシート。入力は「動画ID または URL」の1フィールドだけ
/// （タイトル入力はしない）。`YouTubeURL` で videoID を抽出でき次第サムネイルをプレビュー表示し、
/// Add を有効化する。API キー・バックエンドは不要。`AudioImportLessonView` の Form + Cancel/Add に倣う。
struct YouTubeAddView: View {
    /// 追加先のレッスン。nil の場合はフォーム内のレッスン選択で選ぶ（Content タブの YouTube セグメント用）。
    /// YouTube はレッスン必須（to-one）のため、レッスンが1つも無ければフォームを出さず案内を表示する。
    let fixedLesson: Lesson?
    /// 追加が完了したときに呼ぶ任意コールバック。Phase 4 のタイプ選択フローで、
    /// 外側のシート全体を閉じてレッスンへ戻すのに使う。既定 nil（単体シートでは dismiss のみ）。
    var onAdded: (() -> Void)?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Lesson.dateStorage, order: .reverse) private var lessons: [Lesson]

    @State private var input = ""
    /// レッスン割当は UUID で選ぶ（@Model の Picker タグはIDで扱うのが安全）。nil = 既定（最新レッスン）
    @State private var selectedLessonID: UUID?

    init(lesson: Lesson? = nil, onAdded: (() -> Void)? = nil) {
        self.fixedLesson = lesson
        self.onAdded = onAdded
    }

    /// 現在の入力から抽出できた videoID（抽出不可なら nil）
    private var extractedVideoID: String? {
        YouTubeURL.videoID(from: input)
    }

    /// 追加先レッスン。固定レッスン > メニュー選択 > 最新レッスン の順で決める。
    private var targetLesson: Lesson? {
        if let fixedLesson { return fixedLesson }
        guard let id = selectedLessonID else { return lessons.first }
        return lessons.first { $0.id == id } ?? lessons.first
    }

    var body: some View {
        NavigationStack {
            Group {
                if fixedLesson == nil && lessons.isEmpty {
                    noLessonState
                } else {
                    form
                }
            }
            .navigationTitle("Add YouTube")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if fixedLesson != nil || !lessons.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Add") { add() }
                            .disabled(extractedVideoID == nil)
                            .accessibilityIdentifier("youtubeAddConfirmButton")
                    }
                }
            }
        }
    }

    private var form: some View {
        Form {
            Section {
                TextField("YouTube video ID or URL", text: $input)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .submitLabel(.done)
                    .accessibilityIdentifier("youtubeAddInput")
            } header: {
                Text("Video ID or URL")
            } footer: {
                // 入力があるのに抽出できないときだけ、明示的に無効を知らせる
                if !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   extractedVideoID == nil {
                    Text("Invalid YouTube video ID or URL")
                        .foregroundStyle(.red)
                }
            }

            // 固定レッスン無しで開いたとき（YouTube セグメントの「+」）は追加先をここで選ぶ。
            // Picker(menu) は選択値ラベルの折り返しを制御できないため、Menu で1行省略表示にする。
            if fixedLesson == nil {
                Section("Lesson") {
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
                        .accessibilityIdentifier("youtubeLessonPicker")
                    }
                }
            }

            if let videoID = extractedVideoID {
                Section("Preview") {
                    YouTubeThumbnail(videoID: videoID)
                        .aspectRatio(16.0 / 9.0, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .listRowInsets(EdgeInsets())
                }
            }
        }
    }

    /// レッスンが1つも無いときの案内（YouTube はレッスン必須のため追加できない）
    private var noLessonState: some View {
        ContentUnavailableView {
            Label("No lessons yet", systemImage: "book.closed")
        } description: {
            Text("YouTube videos belong to a lesson. Create a class and lesson in the Lessons tab first.")
        }
    }

    private func lessonLabel(_ lesson: Lesson) -> String {
        "\(lesson.schoolClass.name) / \(lesson.displayTitle)"
    }

    private func add() {
        guard let videoID = extractedVideoID, let lesson = targetLesson else { return }
        // タイトルは持たせない（表示は videoID で代替）。将来キー不要の oEmbed で補える余地は残す。
        let link = YouTubeLink(lesson: lesson, videoID: videoID)
        modelContext.insert(link)
        modelContext.saveOrLog()
        onAdded?()
        dismiss()
    }
}
