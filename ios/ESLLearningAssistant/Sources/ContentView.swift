import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            LessonsView()
                .tabItem {
                    Label("Lessons", systemImage: "graduationcap")
                }

            WordsView()
                .tabItem {
                    Label("Words", systemImage: "book")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
    }
}

#Preview {
    ContentView()
}
