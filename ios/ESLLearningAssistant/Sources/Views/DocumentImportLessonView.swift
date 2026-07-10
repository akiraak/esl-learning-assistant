import SwiftUI
import SwiftData

/// 文書取り込み時にレッスンを選ぶシート。`.fileImporter` でファイルを選んだ直後に提示し、
/// 選んだレッスン（既定 None＝ライブラリ文書）へ取り込む。Import で実行、Cancel で取り込み中止。
/// 実際の読み込み（セキュリティスコープ付きURLのアクセス）は確定時に `onImport` 側で行う。
/// 音声の `AudioImportLessonView` の文書版。
struct DocumentImportLessonView: View {
    /// `.fileImporter` で選ばれた取り込み対象のURL群（セキュリティスコープ付き）
    let urls: [URL]
    /// 選んだレッスン（nil = 未割当のライブラリ文書）で取り込みを実行するコールバック
    let onImport: (Lesson?) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Lesson.dateStorage, order: .reverse) private var lessons: [Lesson]

    /// レッスン割当は UUID で選ぶ（@Model の Picker タグはIDで扱うのが安全）。nil = 未割当
    @State private var selectedLessonID: UUID?

    var body: some View {
        NavigationStack {
            Form {
                Section(urls.count == 1 ? "File" : "Files (\(urls.count))") {
                    ForEach(urls, id: \.self) { url in
                        Text(url.lastPathComponent)
                            .lineLimit(2)
                    }
                }
                Section("Lesson") {
                    Picker("Lesson", selection: $selectedLessonID) {
                        Text("None").tag(UUID?.none)
                        ForEach(lessons) { lesson in
                            Text("\(lesson.schoolClass.name) / \(lesson.displayTitle)")
                                .tag(UUID?.some(lesson.id))
                        }
                    }
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Import") {
                        onImport(lessons.first { $0.id == selectedLessonID })
                        dismiss()
                    }
                    .accessibilityIdentifier("documentImportConfirmButton")
                }
            }
        }
    }

    private var navigationTitle: String {
        urls.count == 1 ? "Import Document" : "Import \(urls.count) Files"
    }
}
