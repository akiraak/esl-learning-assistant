import SwiftUI
import SwiftData

/// 音声クリップのタイトル編集とレッスン割当（未割当も可）。
struct AudioClipEditView: View {
    @Bindable var clip: AudioClip

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Lesson.createdAt, order: .reverse) private var lessons: [Lesson]

    /// レッスン割当は UUID で選ぶ（@Model の Picker タグはIDで扱うのが安全）。nil = 未割当
    @State private var selectedLessonID: UUID?

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("Title", text: $clip.title)
                }
                Section("Lesson") {
                    Picker("Lesson", selection: $selectedLessonID) {
                        Text("None").tag(UUID?.none)
                        ForEach(lessons) { lesson in
                            Text("\(lesson.schoolClass.name) / \(lesson.title)")
                                .tag(UUID?.some(lesson.id))
                        }
                    }
                }
            }
            .navigationTitle("Edit Audio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { save() }
                }
            }
            .onAppear { selectedLessonID = clip.lesson?.id }
        }
    }

    private func save() {
        clip.lesson = lessons.first { $0.id == selectedLessonID }
        modelContext.saveOrLog()
        dismiss()
    }
}
