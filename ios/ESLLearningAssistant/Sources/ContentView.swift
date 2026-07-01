import SwiftUI

struct ContentView: View {
    @State private var router = AppRouter()

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
                .tag(AppTab.words)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(AppTab.settings)
        }
        .environment(router)
    }
}

#Preview {
    ContentView()
}
