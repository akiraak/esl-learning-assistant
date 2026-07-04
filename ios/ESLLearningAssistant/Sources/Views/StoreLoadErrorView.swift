import SwiftUI

/// SwiftData ストアの読み込みに失敗したときに表示する画面。
/// 読み込み失敗を無視して「データゼロ」のまま動き続けると、保存も表示もできない状態に
/// 誰も気付けないため（マイグレーション失敗バグの再発防止）、失敗を明示する。
struct StoreLoadErrorView: View {
    let error: Error

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text("Failed to Load Data")
                .font(.title2)
                .fontWeight(.semibold)
            Text("The app's database could not be opened, so your data cannot be read or saved right now. Your data is still on this device. Updating the app to the latest version should fix this.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text(String(describing: error))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(24)
    }
}

#Preview {
    StoreLoadErrorView(
        error: NSError(
            domain: NSCocoaErrorDomain,
            code: 134110,
            userInfo: [NSLocalizedDescriptionKey: "An error occurred during persistent store migration."]
        )
    )
}
