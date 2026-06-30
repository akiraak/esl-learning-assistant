import SwiftUI

struct QuizView: View {
    var body: some View {
        NavigationStack {
            PlaceholderContent(
                systemImage: "checkmark.circle",
                title: "問題",
                message: "教科書内容から練習問題を自動生成する機能は Phase 3 で実装します。"
            )
            .navigationTitle("問題")
        }
    }
}

#Preview {
    QuizView()
}
