import SwiftUI

/// レッスンコンテンツ一覧の YouTube 行。左にサムネイル（再生バッジ付き）、右に表示名と追加日。
/// `PhotoRow` / `AudioClipRow` と同じ 44pt サムネイル + タイトル + 日付のレイアウトに揃える。
/// `LessonsView` と `YouTubeLibraryView` で共用する（`showsLesson` で紐付くレッスン名を追加表示）。
struct YouTubeRow: View {
    let link: YouTubeLink
    /// 紐付くレッスン名（クラス / レッスン）をサブタイトル表示するか（横断一覧用）
    var showsLesson = false

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        HStack(spacing: 12) {
            YouTubeThumbnail(videoID: link.videoID, badgeFont: .title3)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(link.displayTitle)
                    .lineLimit(1)
                if showsLesson {
                    Text("\(link.lesson.schoolClass.name) / \(link.lesson.displayTitle)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
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
        // タイトル未取得なら oEmbed で補完する（表示のたびに再取得しないよう title==nil のときだけ）
        .task(id: link.id) {
            await backfillTitleIfNeeded()
        }
    }

    /// `title` が未設定なら oEmbed で取得して永続化する。取得済み・取得失敗時は videoID 表示のまま。
    private func backfillTitleIfNeeded() async {
        guard link.title == nil else { return }
        guard let title = await YouTubeOEmbed.fetchTitle(videoID: link.videoID) else { return }
        // await 中に他経路で入っていないか再確認してから書き込む
        guard link.title == nil else { return }
        link.title = title
        modelContext.saveOrLog()
    }
}
