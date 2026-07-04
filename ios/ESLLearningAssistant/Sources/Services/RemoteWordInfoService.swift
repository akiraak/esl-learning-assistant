import Foundation

/// /api/word-info のレスポンス
struct WordInfoResponse: Decodable {
    let wordInfo: WordAIInfo
    let model: String
    /// サーバ保存済みの返却なら true（表示には使わないがデバッグ用に保持）
    let cached: Bool?
}

@MainActor
protocol WordInfoService {
    /// senseHint 指定時は、その意味の見出し（同綴異義のうちの1つ）に限定して生成する。
    func fetchWordInfo(
        word: String,
        targetLanguage: String,
        context: String?,
        userTranslation: String?,
        regenerate: Bool,
        senseHint: String?
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
        let regenerate: Bool
        let senseHint: String?
    }

    func fetchWordInfo(
        word: String,
        targetLanguage: String,
        context: String?,
        userTranslation: String?,
        regenerate: Bool,
        senseHint: String? = nil
    ) async throws -> WordInfoResponse {
        let data = try await BackendAPI.post(
            path: "api/word-info",
            body: RequestBody(
                word: word,
                targetLanguage: targetLanguage,
                context: context,
                userTranslation: userTranslation,
                regenerate: regenerate,
                senseHint: senseHint
            )
        )
        return try JSONDecoder().decode(WordInfoResponse.self, from: data)
    }
}
