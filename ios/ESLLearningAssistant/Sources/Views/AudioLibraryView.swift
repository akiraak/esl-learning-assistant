import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// `.fileImporter` で選ばれたURL群を、レッスン選択シート（`AudioImportLessonView`）へ
/// 渡すための識別可能ラッパ。`.sheet(item:)` で扱えるようにする。
private struct PendingAudioImport: Identifiable {
    let id = UUID()
    let urls: [URL]
}

/// Content タブの Audio セグメント。iOSの「ファイル」（Dropbox・iCloud・端末内）から取り込んだ
/// 音声（AudioClip）のライブラリ。行タップで再生＋詳細へ遷移（既存 TTSPlayerBar が継続表示）。
/// 詳細画面でタイトル編集・レッスン割当・削除を行う。
/// `ContentTabView` の NavigationStack 配下に埋め込む前提（自前の NavigationStack は持たない）。
/// 再生サービスは詳細 push 中も生かすため親（ContentTabView）が保持して渡す。
struct AudioLibraryView: View {
    @ObservedObject var playback: TTSPlaybackService

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \AudioClip.importedAt, order: .reverse) private var clips: [AudioClip]

    @State private var isShowingFileImporter = false
    /// ファイル選択後、レッスン選択シートへ渡す取り込み待ちURL群
    @State private var pendingImport: PendingAudioImport?
    /// 取り込み（正規化含む）実行中。インジケータ表示＋取り込みボタン無効化に使う
    @State private var isImporting = false
    @State private var importError: String?
    /// 詳細へ push 中のクリップ（行タップで設定 → navigationDestination で遷移）
    @State private var selectedClip: AudioClip?

    var body: some View {
        Group {
            if clips.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(clips) { clip in
                        // 行タップで詳細へ遷移する（再生は詳細画面で行う）。
                        Button {
                            selectedClip = clip
                        } label: {
                            AudioClipRow(clip: clip)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Delete", systemImage: "trash", role: .destructive) { delete(clip) }
                        }
                    }
                    .onDelete(perform: deleteAt)
                }
                .navigationDestination(item: $selectedClip) { clip in
                    AudioDetailView(clip: clip, playback: playback)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingFileImporter = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Import Audio")
                .disabled(isImporting)
            }
        }
        .overlay {
            if isImporting {
                ImportingAudioOverlay()
            }
        }
        .fileImporter(
            isPresented: $isShowingFileImporter,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: true
        ) { result in
            handleFileSelection(result)
        }
        // ファイル選択後にレッスンとノーマライズ ON/OFF を選んでから取り込む
        .sheet(item: $pendingImport) { pending in
            AudioImportLessonView(urls: pending.urls) { lesson, normalize in
                importFiles(pending.urls, into: lesson, normalize: normalize)
            }
        }
        .alert("Import Failed", isPresented: importErrorBinding) {
            Button("OK", role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "")
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No audio yet", systemImage: "waveform")
        } description: {
            Text("Import audio from the Files app (Dropbox, iCloud, on-device).")
        } actions: {
            Button("Import Audio") { isShowingFileImporter = true }
                .buttonStyle(.borderedProminent)
                .disabled(isImporting)
        }
    }

    /// ファイル選択の結果を受け取る。成功時は即取り込まず、レッスン選択シートへ回す。
    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard !urls.isEmpty else { return }
            pendingImport = PendingAudioImport(urls: urls)
        case .failure(let error):
            importError = error.localizedDescription
        }
    }

    /// レッスン選択シートで確定した後に、実際の取り込みを行う。
    /// 正規化はバックグラウンドで数秒かかり得るため async で実行し、間はインジケータを出す。
    private func importFiles(_ urls: [URL], into lesson: Lesson?, normalize: Bool) {
        isImporting = true
        Task {
            let count = await AudioFileImporter.importFiles(
                urls, into: lesson, context: modelContext, normalize: normalize
            )
            isImporting = false
            if count == 0 && !urls.isEmpty {
                importError = "Could not read the selected audio file(s)."
            }
        }
    }

    private var importErrorBinding: Binding<Bool> {
        Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })
    }

    private func isPlaying(_ clip: AudioClip) -> Bool {
        let url = AudioStorage.url(fileName: clip.audioFileName)
        return playback.isActive && playback.currentURL == url
    }

    private func deleteAt(_ offsets: IndexSet) {
        for index in offsets { delete(clips[index]) }
    }

    private func delete(_ clip: AudioClip) {
        if isPlaying(clip) { playback.stop() }
        // 音声ファイル削除・clip 削除・sourceAudio の nullify・保存をまとめて行う
        modelContext.deleteAudioClip(clip)
    }
}

/// 音声ライブラリ 1 行。タイトル＋紐付くレッスン名（あれば）。再生は詳細画面で行う。
struct AudioClipRow: View {
    let clip: AudioClip

    /// 紐付くレッスンのサブタイトル。複数時は先頭＋ "+N"。未割当は nil。
    private var lessonSubtitle: String? {
        let lessons = clip.lessons.sorted { $0.date > $1.date }
        guard let first = lessons.first else { return nil }
        let base = "\(first.schoolClass.name) / \(first.title)"
        return lessons.count > 1 ? "\(base)  +\(lessons.count - 1)" : base
    }

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(clip.title).lineLimit(1)
                if let subtitle = lessonSubtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // 文字起こしの状態を控えめに示す（未実行は何も出さない）
            transcriptStatusBadge

            // 詳細へ遷移できることを示す標準の開示インジケータ
            Image(systemName: "chevron.forward")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    /// 文字起こし状態のミニインジケータ。完了=吹き出し、処理中=スピナー、失敗=警告、未実行=なし。
    @ViewBuilder
    private var transcriptStatusBadge: some View {
        switch clip.processingStatus {
        case .completed:
            Image(systemName: "text.bubble")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .processing:
            ProgressView()
                .controlSize(.mini)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(.orange)
        case .pending:
            EmptyView()
        }
    }
}
