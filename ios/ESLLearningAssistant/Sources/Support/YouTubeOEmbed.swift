import Foundation
import os

/// キー不要の YouTube oEmbed で公開動画のタイトルを取得する。
/// エンドポイント `https://www.youtube.com/oembed?url=<watch URL>&format=json` は
/// API キー不要で `title` 等のメタ情報を返す。取得できなければ nil を返し、
/// 呼び出し側は videoID 表示にフォールバックする（`YouTubeLink.displayTitle`）。
enum YouTubeOEmbed {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "ESLLearningAssistant",
        category: "YouTubeOEmbed"
    )

    /// UIテスト用スタブのタイトルを差し込む UserDefaults キー
    /// （`-uiTestStubYouTubeTitle "..."` の launch 引数で設定）。
    /// 非空なら実ネットワークを呼ばずこの値を返し、タイトル差し替えの E2E を決定的にする。
    static let stubTitleDefaultsKey = "uiTestStubYouTubeTitle"

    /// videoID から動画タイトルを取得する。取得できなければ nil。
    static func fetchTitle(videoID: String) async -> String? {
        // UIテスト用スタブが設定されていれば実ネットワークを介さずそれを返す
        if let stub = UserDefaults.standard.string(forKey: stubTitleDefaultsKey), !stub.isEmpty {
            return stub
        }
        guard let url = endpoint(for: videoID) else { return nil }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                logger.info("oEmbed non-200 for \(videoID, privacy: .public)")
                return nil
            }
            let decoded = try JSONDecoder().decode(Response.self, from: data)
            let title = decoded.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return title.isEmpty ? nil : title
        } catch {
            logger.info("oEmbed fetch failed for \(videoID, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// oEmbed エンドポイント URL を組み立てる。不正な videoID は弾く（純関数・ユニットテスト対象）。
    static func endpoint(for videoID: String) -> URL? {
        guard YouTubeURL.isValidID(videoID) else { return nil }
        var components = URLComponents(string: "https://www.youtube.com/oembed")
        components?.queryItems = [
            URLQueryItem(name: "url", value: "https://www.youtube.com/watch?v=\(videoID)"),
            URLQueryItem(name: "format", value: "json"),
        ]
        return components?.url
    }

    /// oEmbed レスポンスのうち、必要な `title` だけをデコードする。
    private struct Response: Decodable {
        let title: String
    }
}
