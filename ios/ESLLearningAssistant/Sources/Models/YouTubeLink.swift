import Foundation
import SwiftData

/// レッスンに紐づく YouTube 動画リンク。写真・音声と並ぶレッスンコンテンツの1種別。
/// 動画は `videoID`（11桁）だけを保持し、サムネイル・埋め込み再生は videoID から URL を組み立てる。
/// API キーは使わず、ユーザーが動画ID（または URL）を指定して追加する（`YouTubeURL` で抽出）。
/// レッスンへの紐付けは Photo と同じく to-one（必須）。レッスン削除時は cascade で一緒に消える。
@Model
final class YouTubeLink {
    var id: UUID
    var lesson: Lesson
    /// YouTube 動画 ID（11桁 `[A-Za-z0-9_-]`）。入力（動画ID or URL）から抽出して保存する。
    var videoID: String
    /// 動画タイトル。ユーザー入力はしない。既定 nil（表示は videoID で代替）。
    /// 将来キー不要の oEmbed で自動取得する余地としてオプショナルで持つ。
    var title: String?
    var addedAt: Date

    init(
        id: UUID = UUID(),
        lesson: Lesson,
        videoID: String,
        title: String? = nil,
        addedAt: Date = .now
    ) {
        self.id = id
        self.lesson = lesson
        self.videoID = videoID
        self.title = title
        self.addedAt = addedAt
    }
}

extension YouTubeLink {
    /// 標準の視聴用 URL（`watch?v=`）。
    var watchURL: URL? {
        URL(string: "https://www.youtube.com/watch?v=\(videoID)")
    }

    /// アプリ内 WebView 埋め込み再生用 URL（cookie を使わない nocookie ドメイン）。
    var embedURL: URL? {
        URL(string: "https://www.youtube-nocookie.com/embed/\(videoID)")
    }

    /// 一覧サムネイル URL（中解像度）。
    var thumbnailURL: URL? {
        URL(string: "https://img.youtube.com/vi/\(videoID)/mqdefault.jpg")
    }

    /// 一覧表示名。タイトルが無ければ videoID を表示する。
    var displayTitle: String {
        if let title, !title.isEmpty { return title }
        return videoID
    }
}
