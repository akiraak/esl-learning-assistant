import SwiftUI

@main
struct ESLLearningAssistantApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [Class.self, Lesson.self, Photo.self])
    }
}
