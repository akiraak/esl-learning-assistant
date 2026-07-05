import Foundation

/// /api/writing-feedback のレスポンス feedback 部分（backend/src/writingFeedback.ts）
struct WritingFeedbackPayload: Decodable {
    let correctedText: String
    let explanation: String
}

/// /api/writing-feedback のレスポンス全体
struct WritingFeedbackResponse: Decodable {
    let feedback: WritingFeedbackPayload
    let model: String
}

@MainActor
protocol WritingFeedbackService {
    func fetchFeedback(
        englishText: String,
        japaneseText: String,
        explanationLanguage: String
    ) async throws -> WritingFeedbackResponse
}

/// バックエンド（Claude API 中継）と通信し、英作文の添削結果を取得する。
/// 作文本文は毎回異なりキャッシュが効かないため、サーバは保存せず常に生成する。
@MainActor
final class RemoteWritingFeedbackService: WritingFeedbackService {
    private struct RequestBody: Encodable {
        let englishText: String
        let japaneseText: String
        let explanationLanguage: String
    }

    func fetchFeedback(
        englishText: String,
        japaneseText: String,
        explanationLanguage: String
    ) async throws -> WritingFeedbackResponse {
        let data = try await BackendAPI.post(
            path: "api/writing-feedback",
            body: RequestBody(
                englishText: englishText,
                japaneseText: japaneseText,
                explanationLanguage: explanationLanguage
            ),
            // 作文添削は sonnet で数千文字を生成しうるため既定60秒だと切れることがある
            timeout: 120
        )
        return try JSONDecoder().decode(WritingFeedbackResponse.self, from: data)
    }
}
