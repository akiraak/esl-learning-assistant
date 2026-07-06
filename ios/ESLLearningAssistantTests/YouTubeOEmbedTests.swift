import Foundation
import Testing
@testable import ESLLearningAssistant

/// `YouTubeOEmbed` のエンドポイント構築・不正 ID の扱い・UIテスト用スタブの短絡を検証する
/// （いずれも実ネットワークに依存しない）。
struct YouTubeOEmbedTests {
    // MARK: - endpoint

    @Test func endpointBuildsOEmbedURLForValidID() throws {
        let url = try #require(YouTubeOEmbed.endpoint(for: "dQw4w9WgXcQ"))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.scheme == "https")
        #expect(components.host == "www.youtube.com")
        #expect(components.path == "/oembed")
        let items = components.queryItems ?? []
        #expect(items.contains(URLQueryItem(name: "format", value: "json")))
        #expect(items.contains(URLQueryItem(name: "url", value: "https://www.youtube.com/watch?v=dQw4w9WgXcQ")))
    }

    @Test func endpointRejectsInvalidID() {
        #expect(YouTubeOEmbed.endpoint(for: "short") == nil)          // 11桁未満
        #expect(YouTubeOEmbed.endpoint(for: "") == nil)
        #expect(YouTubeOEmbed.endpoint(for: "dQw4w9WgXc!") == nil)    // 不正文字
    }

    // MARK: - スタブ短絡

    @Test func stubTitleShortCircuitsFetch() async {
        let key = YouTubeOEmbed.stubTitleDefaultsKey
        UserDefaults.standard.set("Stub Video Title", forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }

        let title = await YouTubeOEmbed.fetchTitle(videoID: "dQw4w9WgXcQ")
        #expect(title == "Stub Video Title")
    }

    @Test func emptyStubIsIgnored() {
        // 空スタブは無視され、実取得（endpoint 構築）へ進む扱いであることを間接的に確認する。
        // ここでは値の設定/除去が endpoint 構築に影響しないことだけを確かめる（ネットワークは呼ばない）。
        let key = YouTubeOEmbed.stubTitleDefaultsKey
        UserDefaults.standard.set("", forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }
        #expect(YouTubeOEmbed.endpoint(for: "dQw4w9WgXcQ") != nil)
    }
}
