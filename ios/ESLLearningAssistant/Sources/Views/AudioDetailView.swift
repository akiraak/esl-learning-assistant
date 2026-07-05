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

    /// レッスン追加シートの提示中フラグ
    @State private var isAddingLesson = false
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
