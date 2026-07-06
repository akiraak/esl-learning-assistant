import SwiftUI

/// videoID から YouTube のサムネイル画像を表示する共通ビュー。中央に ▶ の再生バッジを重ね、
/// 一覧行・追加プレビュー・詳細で見た目を揃える。サイズ・角丸は呼び出し側で `.frame`/
/// `.aspectRatio` して決める（このビュー自身は与えられた領域を埋める）。
/// 画像は標準 `AsyncImage` で取得する（新規依存を増やさない）。
struct YouTubeThumbnail: View {
    let videoID: String
    /// 中央の再生バッジのサイズ。小さいサムネイル（行）では控えめに、大きいプレビューでは大きく。
    var badgeFont: Font = .largeTitle
    var cornerRadius: CGFloat = 8

    var body: some View {
        AsyncImage(url: YouTubeLink.thumbnailURL(for: videoID)) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            case .empty:
                placeholder { ProgressView() }
            case .failure:
                placeholder {
                    Image(systemName: "play.rectangle")
                        .foregroundStyle(.secondary)
                }
            @unknown default:
                placeholder { Color.clear }
            }
        }
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .overlay {
            // 動画（YouTube）だと一目で分かるよう再生バッジを重ねる
            Image(systemName: "play.circle.fill")
                .font(badgeFont)
                .foregroundStyle(.white, .black.opacity(0.45))
                .shadow(radius: 2)
        }
    }

    private func placeholder<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ZStack {
            Rectangle().fill(.secondary.opacity(0.15))
            content()
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        YouTubeThumbnail(videoID: "dQw4w9WgXcQ", badgeFont: .title3)
            .frame(width: 44, height: 44)
        YouTubeThumbnail(videoID: "dQw4w9WgXcQ")
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .frame(maxWidth: .infinity)
    }
    .padding()
}
