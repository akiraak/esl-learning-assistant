import MarkdownUI
import SwiftUI
import SwiftData

/// 音声クリップの詳細。共有の `TTSPlaybackService` で再生し、下部の `TTSPlayerBar` は
/// この画面の `safeAreaInset` に置く（再生UIは一覧ではなく詳細画面に集約する）。
/// タイトル編集・文字起こし＋翻訳・レッスンの追加/変更/解除・削除をこの画面に集約する。
struct AudioDetailView: View {
    @Bindable var clip: AudioClip
    @ObservedObject var playback: TTSPlaybackService

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// レッスン追加シートの提示中フラグ
    @State private var isAddingLesson = false
    @State private var isConfirmingDelete = false

    /// 音声→英文文字起こし＋日本語訳。写真OCRと同型の Remote 実装（差し替え可能に protocol 型で保持）。
    private let transcriptionService: TranscriptionTranslationService = RemoteTranscriptionTranslationService()

    private var audioURL: URL { AudioStorage.url(fileName: clip.audioFileName) }
    /// この clip が今アクティブ（再生中 or 一時停止でロード済み）か
    private var isActiveClip: Bool { playback.isActive && playback.currentURL == audioURL }
    /// 単語タップ登録の紐付け先。紐付くレッスンのうち最新のものを使う（未割当なら nil）。
    private var primaryLesson: Lesson? {
        clip.lessons.sorted { $0.createdAt > $1.createdAt }.first
    }

    var body: some View {
        Form {
            Section("Title") {
                TextField("Title", text: $clip.title)
                    .onChange(of: clip.title) { modelContext.saveOrLog() }
            }

            transcriptSection

            Section {
                // 単語詳細（Appears in Lessons）と同型：一覧＋スワイプ解除＋追加ボタン
                let linked = clip.lessons.sorted { $0.createdAt > $1.createdAt }
                ForEach(linked) { lesson in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(lesson.title)
                            .foregroundStyle(.primary)
                        Text(lesson.schoolClass.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            unlink(lesson)
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                }
                Button {
                    isAddingLesson = true
                } label: {
                    Label("Add to Lesson", systemImage: "plus.circle")
                }
                .accessibilityIdentifier("audioAddToLessonButton")
            } header: {
                Text("Lessons")
            }

            Section {
                Button(role: .destructive) {
                    isConfirmingDelete = true
                } label: {
                    // destructiveロールは文字だけ赤くなりアイコンがtintのままなので、アイコンも揃える
                    Label("Delete Audio", systemImage: "trash")
                        .foregroundStyle(.red)
                }
                .accessibilityIdentifier("audioDeleteButton")
            }
        }
        .navigationTitle(clip.title)
        .navigationBarTitleDisplayMode(.inline)
        .animation(.snappy(duration: 0.25), value: clip.processingStatus)
        // 文字起こし英文の単語タップ→登録/詳細遷移。紐付くレッスンがあれば出現記録も残す。
        // （音声由来を示す sourceAudio 相当は未実装のため sourcePhoto は渡さない = Phase 6 の課題）
        .wordTapRegistration(lesson: primaryLesson)
        // 再生中だけ画面下部にプレイヤーを差し込む（再生UIはこの詳細画面に集約）
        .safeAreaInset(edge: .bottom) {
            if playback.isActive {
                TTSPlayerBar(playback: playback)
            }
        }
        .onAppear {
            // 自動再生はせず、一時停止状態でロードしてプレイヤーを表示する
            playback.prepare(url: audioURL)
        }
        .sheet(isPresented: $isAddingLesson) {
            // 既にリンク済みのレッスンは除外して二重リンクを防ぐ
            let linkedLessonIDs = Set(clip.lessons.map(\.id))
            WordLessonPickerView(excludedLessonIDs: linkedLessonIDs, title: "Add to Lesson") { lesson in
                link(lesson)
            }
        }
        .confirmationDialog(
            "Delete this audio?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { delete() }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Transcript

    /// 文字起こし＋翻訳セクション。`processingStatus` で表示を分岐する
    /// （未実行=手動ボタン / 処理中=インジケータ / 失敗=エラー＋再試行 / 完了=英文＋訳＋再実行）。
    @ViewBuilder
    private var transcriptSection: some View {
        Section {
            switch clip.processingStatus {
            case .pending:
                transcribeButton(title: "Transcribe", systemImage: "text.bubble")
            case .processing:
                ProcessingIndicatorView(label: "Transcribing & translating…")
                    .padding(.vertical, 4)
            case .failed:
                VStack(alignment: .leading, spacing: 8) {
                    TappableEnglishText(text: "Transcription & translation failed", color: .red)
                        .foregroundStyle(.red)
                    if let message = clip.processingErrorMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    transcribeButton(title: "Try Again", systemImage: "arrow.clockwise")
                }
            case .completed:
                completedTranscript
            }
        } header: {
            Text("Transcript")
        }
    }

    /// 完了時の本文表示：英文（単語タップ可）＋日本語訳（Markdown）＋再実行ボタン。
    @ViewBuilder
    private var completedTranscript: some View {
        VStack(alignment: .leading, spacing: 12) {
            TappableEnglishText(text: "Transcript (English)")
                .font(.headline)
            TappableMarkdown(markdown: clip.transcriptText ?? "")

            Divider()

            TappableEnglishText(text: "Translation")
                .font(.headline)
            Markdown(clip.translatedText ?? "")
                .markdownHeadingHighlight()

            Divider()

            transcribeButton(title: "Re-transcribe", systemImage: "arrow.clockwise")
        }
    }

    private func transcribeButton(title: String, systemImage: String) -> some View {
        Button {
            Task { await runTranscription() }
        } label: {
            Label(title, systemImage: systemImage)
        }
        .buttonStyle(.bordered)
    }

    /// 文字起こし＋翻訳を実行する。サービスが `clip` を更新し、明示保存で永続化する
    /// （autosave 任せだと直後にアプリを強制終了された場合に失われるため）。
    private func runTranscription() async {
        await transcriptionService.process(clip)
        modelContext.saveOrLog()
    }

    /// レッスンに紐付ける（既にリンク済みなら何もしない）
    private func link(_ lesson: Lesson) {
        guard !clip.lessons.contains(where: { $0.id == lesson.id }) else { return }
        clip.lessons.append(lesson)
        modelContext.saveOrLog()
    }

    /// 指定レッスンとの紐付けを解除する（クリップ本体・レッスンは残る）
    private func unlink(_ lesson: Lesson) {
        clip.lessons.removeAll { $0.id == lesson.id }
        modelContext.saveOrLog()
    }

    private func delete() {
        if isActiveClip { playback.stop() }
        AudioStorage.delete(fileName: clip.audioFileName)
        modelContext.delete(clip)
        modelContext.saveOrLog()
        dismiss()
    }
}
