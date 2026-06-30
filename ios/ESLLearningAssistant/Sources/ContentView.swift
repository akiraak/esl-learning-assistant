import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            CaptureView()
                .tabItem {
                    Label("撮影", systemImage: "camera")
                }

            VocabularyView()
                .tabItem {
                    Label("単語帳", systemImage: "book")
                }

            QuizView()
                .tabItem {
                    Label("問題", systemImage: "checkmark.circle")
                }

            SettingsView()
                .tabItem {
                    Label("設定", systemImage: "gearshape")
                }
        }
    }
}

#Preview {
    ContentView()
}
