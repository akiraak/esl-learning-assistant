import SwiftUI

struct VocabularyView: View {
    var body: some View {
        NavigationStack {
            PlaceholderContent(
                systemImage: "book",
                title: "単語帳",
                message: "単語の登録・翻訳・復習機能は Phase 2 で実装します。"
            )
            .navigationTitle("単語帳")
        }
    }
}

#Preview {
    VocabularyView()
}
