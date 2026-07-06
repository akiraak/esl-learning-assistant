import SwiftUI
import SwiftData

@main
struct ESLLearningAssistantApp: App {
    /// ストア読み込み失敗（マイグレーション失敗等）を無言で「データゼロ」にしないため、
    /// コンテナは明示的に生成して失敗時はエラー画面を出す
    private let modelContainerResult: Result<ModelContainer, Error>

    init() {
        AppSettingsKeys.migrateLegacyTTSEngineIfNeeded()
        do {
            let container = try ModelContainer(
                for: Class.self, Lesson.self, Photo.self, Word.self, WordOccurrence.self, Composition.self, AudioClip.self, YouTubeLink.self
            )
            modelContainerResult = .success(container)
        } catch {
            modelContainerResult = .failure(error)
        }
    }

    var body: some Scene {
        WindowGroup {
            switch modelContainerResult {
            case .success(let container):
                ContentView()
                    .modelContainer(container)
            case .failure(let error):
                StoreLoadErrorView(error: error)
            }
        }
    }
}
