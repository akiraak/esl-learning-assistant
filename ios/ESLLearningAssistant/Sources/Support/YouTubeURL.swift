import Foundation

/// YouTube の動画IDまわりのパース。ユーザー入力（動画ID直接／各種 YouTube URL）から
/// 11桁の videoID を取り出す。API キーやネットワークは使わない純ロジック。
enum YouTubeURL {
    /// videoID として妥当な文字集合（`[A-Za-z0-9_-]`）。
    private static let idCharacters = Set(
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-"
    )

    /// 11桁の妥当な YouTube 動画IDか。
    static func isValidID(_ candidate: String) -> Bool {
        candidate.count == 11 && candidate.allSatisfy { idCharacters.contains($0) }
    }

    /// 入力から videoID を抽出する。抽出できなければ nil。
    /// 対応: 動画ID直接 / `youtu.be/<id>` / `watch?v=<id>` / `/shorts/<id>` /
    /// `/embed/<id>` / `/live/<id>` / `/v/<id>`（余分なクエリ・タイムスタンプは無視）。
    static func videoID(from input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // 1) 動画IDそのもの
        if isValidID(trimmed) { return trimmed }

        // 2) URL として解釈（スキーム省略にも対応）
        let urlString = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let components = URLComponents(string: urlString),
              let host = components.host?.lowercased(),
              host.contains("youtu") else {
            return nil
        }

        let segments = components.path.split(separator: "/").map(String.init)

        // youtu.be/<id>
        if host == "youtu.be" || host.hasSuffix(".youtu.be") {
            if let first = segments.first, isValidID(first) { return first }
            return nil
        }

        // youtube.com/watch?v=<id>
        if let value = components.queryItems?.first(where: { $0.name == "v" })?.value,
           isValidID(value) {
            return value
        }

        // /shorts/<id>, /embed/<id>, /live/<id>, /v/<id>
        if let markerIndex = segments.firstIndex(where: { ["shorts", "embed", "live", "v"].contains($0) }),
           markerIndex + 1 < segments.count,
           isValidID(segments[markerIndex + 1]) {
            return segments[markerIndex + 1]
        }

        return nil
    }
}
