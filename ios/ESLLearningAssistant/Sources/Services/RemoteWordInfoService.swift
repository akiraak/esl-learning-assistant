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

enum WordInfoServiceError: Error {
    case invalidURL
    case serverError(statusCode: Int)
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
        let baseURLString = UserDefaults.standard.string(forKey: AppSettingsKeys.backendBaseURL)
            ?? AppSettingsKeys.defaultBackendBaseURL

        guard let url = URL(string: baseURLString)?.appendingPathComponent("api/word-info") else {
            throw WordInfoServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            RequestBody(
                word: word,
                targetLanguage: targetLanguage,
                context: context,
                userTranslation: userTranslation
            )
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw WordInfoServiceError.serverError(statusCode: statusCode)
        }
        return try JSONDecoder().decode(WordInfoResponse.self, from: data)
    }
}
