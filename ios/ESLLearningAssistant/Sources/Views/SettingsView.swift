import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            PlaceholderContent(
                systemImage: "gearshape",
                title: "設定",
                message: "翻訳先の母語設定などはここに実装します。"
            )
            .navigationTitle("設定")
        }
    }
}

#Preview {
    SettingsView()
}
