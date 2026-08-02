import Foundation

/// `GET /api/words` の1語分のサマリ（backend/src/wordsApi.ts の `WordSummary`）。
/// 取り込みに使うのは `word` だけだが、将来の表示・並べ替え用に主要フィールドを保持する。
/// `word` はサーバ保存時に正規化（trim + 小文字化）済み。
struct ServerWordSummary: Decodable {
    let word: String
    let targetLanguage: String
    let meaning: String?
    let partOfSpeech: String?
    let cefrLevel: String?
    let createdAt: String
    let updatedAt: String
}

/// `GET /api/words` のレスポンス
struct ServerWordListResponse: Decodable {
    /// 条件に一致する総件数（ページングの終端判定に使う）
    let total: Int
    let limit: Int
    let offset: Int
    let words: [ServerWordSummary]
}

@MainActor
protocol WordListService {
    func fetchWords(targetLanguage: String, limit: Int, offset: Int) async throws -> ServerWordListResponse
}

/// backend の単語参照 API（`GET /api/words`、docs/plans/archive/word-info-reference-api.md）から
/// サーバ保存済みの単語一覧を取得する。読み取り専用で AI 呼び出し・課金は発生しない。
@MainActor
final class RemoteWordListService: WordListService {
    func fetchWords(targetLanguage: String, limit: Int, offset: Int) async throws -> ServerWordListResponse {
        let data = try await BackendAPI.get(
            path: "api/words",
            queryItems: [
                URLQueryItem(name: "targetLanguage", value: targetLanguage),
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "offset", value: String(offset)),
            ]
        )
        return try JSONDecoder().decode(ServerWordListResponse.self, from: data)
    }
}
