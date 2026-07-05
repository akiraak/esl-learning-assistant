import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// `.fileImporter` で選ばれたURL群を、レッスン選択シート（`AudioImportLessonView`）へ
/// 渡すための識別可能ラッパ。`.sheet(item:)` で扱えるようにする。
private struct PendingAudioImport: Identifiable {
    let id = UUID()
    let urls: [URL]
}

/// Audioタブのトップ。iOSの「ファイル」（Dropbox・iCloud・端末内）から取り込んだ音声
/// （AudioClip）のライブラリ。行タップで再生＋詳細へ遷移（既存 TTSPlayerBar が継続表示）。
/// 詳細画面でタイトル編集・レッスン割当・削除を行う。
struct AudioView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \AudioClip.importedAt, order: .reverse) private var clips: [AudioClip]
    @StateObject private var playback = TTSPlaybackService()

    @State private var isShowingFileImporter = false
    /// ファイル選択後、レッスン選択シートへ渡す取り込み待ちURL群
    @State private var pendingImport: PendingAudioImport?
    @State private var importError: String?
    /// 詳細へ push 中のクリップ（行タップで設定 → navigationDestination で遷移）
    @State private var selectedClip: AudioClip?

    var body: some View {
        NavigationStack {
            Group {
                if clips.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(clips) { clip in
                            // 行タップで詳細へ遷移しつつ、同時に再生も開始する。
                            // NavigationLink + simultaneousGesture だとタップを食い合って遷移しないため、
                            // Button で明示的に遷移先を指定する（navigationDestination で push）。
                            Button {
                                togglePlay(clip)
                                selectedClip = clip
                            } label: {
                                AudioClipRow(clip: clip, isPlaying: isPlaying(clip)) {
                                    togglePlay(clip)
                                }
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
            .navigationTitle("Audio")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingFileImporter = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Import Audio")
                }
            }
            .fileImporter(
                isPresented: $isShowingFileImporter,
                allowedContentTypes: [.audio],
                allowsMultipleSelection: true
            ) { result in
                handleFileSelection(result)
            }
            // ファイル選択後にレッスンを選んでから取り込む
            .sheet(item: $pendingImport) { pending in
                AudioImportLessonView(urls: pending.urls) { lesson in
                    importFiles(pending.urls, into: lesson)
                }
            }
            .alert("Import Failed", isPresented: importErrorBinding) {
                Button("OK", role: .cancel) { importError = nil }
            } message: {
                Text(importError ?? "")
            }
        }
        // 再生UIは AudioDetailView の safeAreaInset に集約する（一覧には出さない）
        .onDisappear { playback.stop() }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No audio yet", systemImage: "waveform")
        } description: {
            Text("Import audio from the Files app (Dropbox, iCloud, on-device).")
        } actions: {
            Button("Import Audio") { isShowingFileImporter = true }
                .buttonStyle(.borderedProminent)
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
    private func importFiles(_ urls: [URL], into lesson: Lesson?) {
        let count = AudioFileImporter.importFiles(urls, into: lesson, context: modelContext)
        if count == 0 && !urls.isEmpty {
            importError = "Could not read the selected audio file(s)."
        }
    }

    private var importErrorBinding: Binding<Bool> {
        Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })
    }

    private func isPlaying(_ clip: AudioClip) -> Bool {
        let url = AudioStorage.url(fileName: clip.audioFileName)
        return playback.isActive && playback.currentURL == url
    }

    private func togglePlay(_ clip: AudioClip) {
        let url = AudioStorage.url(fileName: clip.audioFileName)
        if playback.isActive && playback.currentURL == url {
            playback.stop()
        } else {
            playback.play(url: url)
        }
    }

    private func deleteAt(_ offsets: IndexSet) {
        for index in offsets { delete(clips[index]) }
    }

    private func delete(_ clip: AudioClip) {
        if isPlaying(clip) { playback.stop() }
        AudioStorage.delete(fileName: clip.audioFileName)
        modelContext.delete(clip)
        modelContext.saveOrLog()
    }
}

/// 音声ライブラリ 1 行。タイトル＋紐付くレッスン名（あれば）＋再生/停止ボタン。
struct AudioClipRow: View {
    let clip: AudioClip
    let isPlaying: Bool
    let onPlayToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(clip.title).lineLimit(1)
                if let lesson = clip.lesson {
                    Text("\(lesson.schoolClass.name) / \(lesson.title)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Button(action: onPlayToggle) {
                Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                    .font(.title3)
            }
            .buttonStyle(.borderless)
        }
    }
}
