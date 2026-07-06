import SwiftUI
import SwiftData

/// YouTube 動画をレッスンに追加するシート。入力は「動画ID または URL」の1フィールドだけ
/// （タイトル入力はしない）。`YouTubeURL` で videoID を抽出でき次第サムネイルをプレビュー表示し、
/// Add を有効化する。API キー・バックエンドは不要。`AudioImportLessonView` の Form + Cancel/Add に倣う。
struct YouTubeAddView: View {
    /// 追加先のレッスン
    let lesson: Lesson
    /// 追加が完了したときに呼ぶ任意コールバック。Phase 4 のタイプ選択フローで、
    /// 外側のシート全体を閉じてレッスンへ戻すのに使う。既定 nil（単体シートでは dismiss のみ）。
    var onAdded: (() -> Void)?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var input = ""

    init(lesson: Lesson, onAdded: (() -> Void)? = nil) {
        self.lesson = lesson
        self.onAdded = onAdded
    }

    /// 現在の入力から抽出できた videoID（抽出不可なら nil）
    private var extractedVideoID: String? {
        YouTubeURL.videoID(from: input)
    }

    var body: some View {
        NavigationStack {
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

                if let videoID = extractedVideoID {
                    Section("Preview") {
                        YouTubeThumbnail(videoID: videoID)
                            .aspectRatio(16.0 / 9.0, contentMode: .fit)
                            .frame(maxWidth: .infinity)
                            .listRowInsets(EdgeInsets())
                    }
                }
            }
            .navigationTitle("Add YouTube")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") { add() }
                        .disabled(extractedVideoID == nil)
                        .accessibilityIdentifier("youtubeAddConfirmButton")
                }
            }
        }
    }

    private func add() {
        guard let videoID = extractedVideoID else { return }
        // タイトルは持たせない（表示は videoID で代替）。将来キー不要の oEmbed で補える余地は残す。
        let link = YouTubeLink(lesson: lesson, videoID: videoID)
        modelContext.insert(link)
        modelContext.saveOrLog()
        onAdded?()
        dismiss()
    }
}
