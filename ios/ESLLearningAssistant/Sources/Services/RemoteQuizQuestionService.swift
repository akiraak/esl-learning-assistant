import Foundation

/// サーバ保存の復習クイズ問題（/api/quiz-questions/*）の取得・生成トリガ。
/// 出題はサーバ問題のみ（端末内では生成しない）。問題が無い単語は出題対象外になる。
struct RemoteQuizQuestionService {
    /// サーバのキャッシュキー正規化（backend db.ts normalizeWordKey）と同じ
    static func normalizeWordKey(_ word: String) -> String {
        word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private struct QueryRequestBody: Encodable {
        let words: [String]
        let targetLanguage: String
    }

    // 壊れた問題 JSON が1件あっても他の問題を捨てないよう、要素単位でデコードする
    private struct LenientQuestion: Decodable {
        let question: ReviewQuestion?

        init(from decoder: Decoder) throws {
            question = try? ReviewQuestion(from: decoder)
        }
    }

    private struct QueryResponseBody: Decodable {
        let questions: [String: [LenientQuestion]]
    }

    /// 複数単語分の保存済み問題をまとめて取得する。
    /// 返り値のキーは正規化済み単語（normalizeWordKey）。問題が無い単語はキーごと含まれない。
    func fetchQuestions(words: [String], targetLanguage: String) async throws -> [String: [ReviewQuestion]] {
        let data = try await BackendAPI.post(
            path: "api/quiz-questions/query",
            body: QueryRequestBody(words: words, targetLanguage: targetLanguage)
        )
        let response = try JSONDecoder().decode(QueryResponseBody.self, from: data)
        return response.questions.mapValues { $0.compactMap(\.question) }
            .filter { !$0.value.isEmpty }
    }

    private struct GenerateRequestBody: Encodable {
        let word: String
        let targetLanguage: String
        let regenerate: Bool
    }

    /// サーバでの問題生成をトリガする（生成済みならサーバ側でキャッシュ返しになる）。
    /// 単語情報の生成成功後と、セッション開始時に問題が無かった単語の自己修復に使う。
    func triggerGeneration(word: String, targetLanguage: String, regenerate: Bool = false) async throws {
        _ = try await BackendAPI.post(
            path: "api/quiz-questions/generate",
            body: GenerateRequestBody(word: word, targetLanguage: targetLanguage, regenerate: regenerate)
        )
    }
}
