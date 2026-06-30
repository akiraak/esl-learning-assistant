import SwiftUI

struct CaptureView: View {
    var body: some View {
        NavigationStack {
            PlaceholderContent(
                systemImage: "camera",
                title: "撮影",
                message: "教科書ページを撮影して OCR・翻訳する機能は Phase 1 で実装します。"
            )
            .navigationTitle("撮影")
        }
    }
}

#Preview {
    CaptureView()
}
