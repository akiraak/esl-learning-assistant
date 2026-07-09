import SwiftUI
import SwiftData

struct ContentView: View {
    @State private var router = AppRouter()
    @Environment(\.modelContext) private var modelContext
    // Words タブのバッジ用。復習状態は埋め込み Codable のため #Predicate は使えず、
    // 全件取得してメモリ内で isDue 判定する（件数は小さい）
    @Query private var words: [Word]

    /// 今日の復習対象の件数（Words タブのバッジに出す。0 なら非表示）
    private var dueCount: Int {
        words.filter { ReviewScheduler.isDue($0.reviewState) }.count
    }

    var body: some View {
        TabView(selection: $router.selectedTab) {
            LessonsView()
                .tabItem {
                    Label("Lessons", systemImage: "graduationcap")
                }
                .tag(AppTab.lessons)

            WordsView()
                .tabItem {
                    Label("Words", systemImage: "book")
                }
                .badge(dueCount)
                .tag(AppTab.words)

            CompositionsView()
                .tabItem {
                    Label("Writing", systemImage: "pencil.and.scribble")
                }
                .tag(AppTab.writing)

            // タブは5個まで（6個以上は iOS の More タブに入り、More のナビゲーションバーと
            // 各タブの NavigationStack が二重になる）。音声・文書は Content タブに統合する。
            ContentTabView()
                .tabItem {
                    Label("Content", systemImage: "tray.full")
                }
                .tag(AppTab.content)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(AppTab.settings)
        }
        .environment(router)
        .task {
            // MarkdownPlainText 修正に伴うTTSキャッシュのリキー移行（未完了時のみ実行、冪等）
            await TTSCacheRekeyMigration.runIfNeeded(modelContext: modelContext)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Class.self, Lesson.self, Photo.self, Word.self, WordOccurrence.self, Composition.self, AudioClip.self, YouTubeLink.self, Document.self], inMemory: true)
}
