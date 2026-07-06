import SwiftUI

/// レッスンコンテンツ一覧の YouTube 行。左にサムネイル（再生バッジ付き）、右に表示名と追加日。
/// `PhotoRow` / `AudioClipRow` と同じ 44pt サムネイル + タイトル + 日付のレイアウトに揃える。
/// Phase 3 で `LessonsView` の統合コンテンツ一覧から使うため非 private。
struct YouTubeRow: View {
    let link: YouTubeLink

    var body: some View {
        HStack(spacing: 12) {
            YouTubeThumbnail(videoID: link.videoID, badgeFont: .title3)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(link.displayTitle)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(link.addedAt, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Label("YouTube", systemImage: "play.rectangle.fill")
                        .labelStyle(.titleAndIcon)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            // 詳細へ遷移できることを示す標準の開示インジケータ
            Image(systemName: "chevron.forward")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}
