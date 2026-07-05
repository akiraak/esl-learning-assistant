import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Audioタブのトップ。iOSの「ファイル」（Dropbox・iCloud・端末内）から取り込んだ音声
/// （AudioClip）のライブラリ。行タップで再生（既存 TTSPlayerBar）。
/// コンテキストメニューからタイトル編集・レッスン割当・削除。
struct AudioView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \AudioClip.importedAt, order: .reverse) private var clips: [AudioClip]
    @StateObject private var playback = TTSPlaybackService()

    @State private var isShowingFileImporter = false
    @State private var editingClip: AudioClip?
    @State private var importError: String?

    var body: some View {
        NavigationStack {
            Group {
                if clips.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(clips) { clip in
                            AudioClipRow(clip: clip, isPlaying: isPlaying(clip)) {
                                togglePlay(clip)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { togglePlay(clip) }
                            .contextMenu {
                                Button("Edit", systemImage: "pencil") { editingClip = clip }
                                Button("Delete", systemImage: "trash", role: .destructive) { delete(clip) }
                            }
                        }
                        .onDelete(perform: deleteAt)
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
            .sheet(item: $editingClip) { clip in
                AudioClipEditView(clip: clip)
            }
            .fileImporter(
                isPresented: $isShowingFileImporter,
                allowedContentTypes: [.audio],
                allowsMultipleSelection: true
            ) { result in
                handleFileImport(result, into: nil)
            }
            .alert("Import Failed", isPresented: importErrorBinding) {
                Button("OK", role: .cancel) { importError = nil }
            } message: {
                Text(importError ?? "")
            }
            // 再生中だけ画面下部にプレイヤーを差し込む（コンテンツを隠さない）
            .safeAreaInset(edge: .bottom) {
                if playback.isActive {
                    TTSPlayerBar(playback: playback)
                }
            }
        }
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

    private func handleFileImport(_ result: Result<[URL], Error>, into lesson: Lesson?) {
        switch result {
        case .success(let urls):
            let count = AudioFileImporter.importFiles(urls, into: lesson, context: modelContext)
            if count == 0 && !urls.isEmpty {
                importError = "Could not read the selected audio file(s)."
            }
        case .failure(let error):
            importError = error.localizedDescription
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
