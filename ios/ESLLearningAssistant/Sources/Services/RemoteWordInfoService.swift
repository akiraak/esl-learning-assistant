import Foundation

/// /api/word-info のレスポンス
struct WordInfoResponse: Decodable {
    let wordInfo: WordAIInfo
    let model: String
}

@MainActor
protocol WordInfoService {
    func fetchWordInfo(
        word: String,
        targetLanguage: String,
        context: String?,
        userTranslation: String?
    ) async throws -> WordInfoResponse
}

/// バックエンド（仕様書5.2章、Claude API中継）と通信し、単語のAI生成情報を取得する。
@MainActor
final class RemoteWordInfoService: WordInfoService {
    private struct RequestBody: Encodable {
        let word: String
        let targetLanguage: String
        let context: String?
        let userTranslation: String?
    }

    func fetchWordInfo(
        word: String,
        targetLanguage: String,
        context: String?,
        userTranslation: String?
    ) async throws -> WordInfoResponse {
        let data = try await BackendAPI.post(
            path: "api/word-info",
            body: RequestBody(
                word: word,
                targetLanguage: targetLanguage,
                context: context,
                userTranslation: userTranslation
            )
        )
        return try JSONDecoder().decode(WordInfoResponse.self, from: data)
    }
}
