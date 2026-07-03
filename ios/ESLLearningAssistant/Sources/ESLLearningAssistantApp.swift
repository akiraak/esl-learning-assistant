import SwiftUI

@main
struct ESLLearningAssistantApp: App {
    init() {
        AppSettingsKeys.migrateLegacyTTSEngineIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [Class.self, Lesson.self, Photo.self, Word.self, WordOccurrence.self])
    }
}
