import SwiftUI
import SwiftData

/// Audio取り込み時の確認シート。`.fileImporter` でファイルを選んだ直後に提示し、
/// レッスン（既定 None）と音量ノーマライズの ON/OFF を選んで取り込む。
/// Import で実行、Cancel で取り込み中止。
/// 実際の読み込み（セキュリティスコープ付きURLのアクセス）は確定時に `onImport` 側で行う。
struct AudioImportLessonView: View {
    /// `.fileImporter` で選ばれた取り込み対象のURL群（セキュリティスコープ付き）
    let urls: [URL]
    /// レッスン確定済みの文脈（レッスン画面の「＋ → Audio」）から使う場合の固定レッスン。
    /// 指定すると Picker を隠してレッスン名の表示だけにする。nil ならユーザーが選ぶ。
    var fixedLesson: Lesson? = nil
    /// 選んだレッスン（nil = 未割当）と音量ノーマライズの ON/OFF で取り込みを実行するコールバック
    let onImport: (Lesson?, Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Lesson.dateStorage, order: .reverse) private var lessons: [Lesson]

    /// レッスン割当は UUID で選ぶ（@Model の Picker タグはIDで扱うのが安全）。nil = 未割当
    @State private var selectedLessonID: UUID?
    /// 音量ノーマライズの ON/OFF。前回の選択を次回の初期値として引き継ぐ（既定 ON）
    @AppStorage(AppSettingsKeys.audioImportNormalizeEnabled) private var normalizeEnabled = true

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
                    if let fixedLesson {
                        Text("\(fixedLesson.schoolClass.name) / \(fixedLesson.displayTitle)")
                    } else {
                        Picker("Lesson", selection: $selectedLessonID) {
                            Text("None").tag(UUID?.none)
                            ForEach(lessons) { lesson in
                                Text("\(lesson.schoolClass.name) / \(lesson.displayTitle)")
                                    .tag(UUID?.some(lesson.id))
                            }
                        }
                    }
                }
                Section {
                    Toggle("Normalize volume", isOn: $normalizeEnabled)
                        .accessibilityIdentifier("audioNormalizeToggle")
                } footer: {
                    Text("Adjusts quiet recordings to a comfortable volume. Saves as AAC.")
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
                        let lesson = fixedLesson ?? lessons.first { $0.id == selectedLessonID }
                        onImport(lesson, normalizeEnabled)
                        dismiss()
                    }
                    .accessibilityIdentifier("audioImportConfirmButton")
                }
            }
        }
    }

    private var navigationTitle: String {
        urls.count == 1 ? "Import Audio" : "Import \(urls.count) Files"
    }
}
