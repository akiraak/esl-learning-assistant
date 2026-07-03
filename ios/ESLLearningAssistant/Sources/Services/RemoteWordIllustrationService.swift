import Foundation

@MainActor
protocol WordIllustrationService {
    /// 単語イラスト（PNG）を取得する。サーバに保存済みならキャッシュ返却、無ければ生成される。
    func fetchIllustration(word: String, targetLanguage: String, senseIndex: Int) async throws -> Data
}

/// バックエンドの /api/word-illustration（GPT Image 2 中継）と通信し、単語イラストを取得する。
@MainActor
final class RemoteWordIllustrationService: WordIllustrationService {
    private struct RequestBody: Encodable {
        let word: String
        let targetLanguage: String
        let senseIndex: Int
    }

    func fetchIllustration(word: String, targetLanguage: String, senseIndex: Int = 0) async throws -> Data {
        try await BackendAPI.post(
            path: "api/word-illustration",
            body: RequestBody(word: word, targetLanguage: targetLanguage, senseIndex: senseIndex)
        )
    }
}
