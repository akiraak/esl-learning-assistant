import Foundation

/// レッスン詳細のコンテンツ欄で写真・音声・YouTube を1つのリストに束ねるためのビュー層の型。
/// モデルは統合せず（`Photo`/`AudioClip`/`YouTubeLink` はそのまま）、表示時だけ共通の
/// タイムスタンプ(`sortDate`)でマージし降順に並べる。行・タップ・削除は種別ごとに分岐する。
enum LessonContentItem: Identifiable {
    case photo(Photo)
    case audio(AudioClip)
    case youtube(YouTubeLink)

    /// 時系列マージ用の共通タイムスタンプ（写真=撮影日 / 音声=取込日 / YouTube=追加日）。
    var sortDate: Date {
        switch self {
        case .photo(let photo): return photo.capturedAt
        case .audio(let clip): return clip.importedAt
        case .youtube(let link): return link.addedAt
        }
    }

    /// 種別プレフィックス付きの安定 ID（`ForEach` 用。種別間の ID 衝突を避ける）。
    var id: String {
        switch self {
        case .photo(let photo): return "photo-\(photo.id.uuidString)"
        case .audio(let clip): return "audio-\(clip.id.uuidString)"
        case .youtube(let link): return "youtube-\(link.id.uuidString)"
        }
    }
}

extension Lesson {
    /// 写真・音声・YouTube を1つに束ね、追加日時の降順で返す統合コンテンツ一覧。
    var contentItems: [LessonContentItem] {
        let items = photos.map(LessonContentItem.photo)
            + audioClips.map(LessonContentItem.audio)
            + youtubeLinks.map(LessonContentItem.youtube)
        return items.sorted { $0.sortDate > $1.sortDate }
    }
}
