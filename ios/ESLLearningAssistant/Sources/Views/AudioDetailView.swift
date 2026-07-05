import SwiftUI
import SwiftData

/// 音声クリップの詳細。共有の `TTSPlaybackService` で再生し、下部の `TTSPlayerBar` は
/// この画面の `safeAreaInset` に置く（再生UIは一覧ではなく詳細画面に集約する）。
/// タイトル編集・レッスンの追加/変更/解除・削除をこの画面に集約する。
struct AudioDetailView: View {
    @Bindable var clip: AudioClip
    @ObservedObject var playback: TTSPlaybackService

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Lesson.createdAt, order: .reverse) private var lessons: [Lesson]

    /// レッスン割当は UUID で選ぶ（@Model の Picker タグはIDで扱うのが安全）。nil = 未割当
    @State private var selectedLessonID: UUID?
    @State private var isConfirmingDelete = false

    private var audioURL: URL { AudioStorage.url(fileName: clip.audioFileName) }
    /// この clip が今アクティブ（再生中 or 一時停止でロード済み）か
    private var isActiveClip: Bool { playback.isActive && playback.currentURL == audioURL }

    var body: some View {
        Form {
            Section("Title") {
                TextField("Title", text: $clip.title)
                    .onChange(of: clip.title) { modelContext.saveOrLog() }
            }

            Section("Lesson") {
                Picker("Lesson", selection: $selectedLessonID) {
                    Text("None").tag(UUID?.none)
                    ForEach(lessons) { lesson in
                        Text("\(lesson.schoolClass.name) / \(lesson.title)")
                            .tag(UUID?.some(lesson.id))
                    }
                }
                .onChange(of: selectedLessonID) {
                    clip.lesson = lessons.first { $0.id == selectedLessonID }
                    modelContext.saveOrLog()
                }
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
        // 再生中だけ画面下部にプレイヤーを差し込む（再生UIはこの詳細画面に集約）
        .safeAreaInset(edge: .bottom) {
            if playback.isActive {
                TTSPlayerBar(playback: playback)
            }
        }
        .onAppear {
            selectedLessonID = clip.lesson?.id
            // 自動再生はせず、一時停止状態でロードしてプレイヤーを表示する
            playback.prepare(url: audioURL)
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

    private func delete() {
        if isActiveClip { playback.stop() }
        AudioStorage.delete(fileName: clip.audioFileName)
        modelContext.delete(clip)
        modelContext.saveOrLog()
        dismiss()
    }
}
