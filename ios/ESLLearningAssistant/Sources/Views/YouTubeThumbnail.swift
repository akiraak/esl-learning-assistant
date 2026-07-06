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
        // 与えられた枠（44pt 四方や 16:9 など）をこの矩形が確定させ、画像は overlay で
        // その枠を満たす。scaledToFill の画像は枠より大きくなるが、合成後に `.clipped()` で
        // 枠へクリップするため、左右へのあふれ（隣接テキストへの被り）が起きない。
        // ※ AsyncImage 自身に clipped を付けると scaledToFill 後の拡大サイズを基準にクリップされ、
        //   枠をはみ出してしまうため、必ず固定サイズの土台越しにクリップする。
        Rectangle()
            .fill(.secondary.opacity(0.15))
            .overlay {
                AsyncImage(url: YouTubeLink.thumbnailURL(for: videoID)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .empty:
                        ProgressView()
                    case .failure:
                        Image(systemName: "play.rectangle")
                            .foregroundStyle(.secondary)
                    @unknown default:
                        Color.clear
                    }
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
