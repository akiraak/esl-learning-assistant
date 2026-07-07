import Foundation

/// 入力語を辞書見出し語へ正規化する（原形化・綴り訂正）。登録・派生生成の前段で使う。
/// 実装差し替え（テストのフェイク）を可能にするためプロトコルにしておく。
@MainActor
protocol WordNormalizeService {
    /// - Parameter regenerate: true でサーバ側キャッシュを無視して作りなおす。
    func normalize(
        word: String,
        targetLanguage: String,
        regenerate: Bool
    ) async throws -> WordNormalization
}

extension WordNormalizeService {
    /// 通常はサーバのキャッシュを利用（regenerate=false）して呼ぶための簡易版。
    func normalize(word: String, targetLanguage: String) async throws -> WordNormalization {
        try await normalize(word: word, targetLanguage: targetLanguage, regenerate: false)
    }
}

/// バックエンド POST /api/word-normalize と通信して正規化結果を得る。
/// RemoteWordInfoService と同じ流儀（BackendAPI 経由・JSON デコード）。
@MainActor
final class RemoteWordNormalizeService: WordNormalizeService {
    private struct RequestBody: Encodable {
        let word: String
        let targetLanguage: String
        let regenerate: Bool
    }

    func normalize(
        word: String,
        targetLanguage: String,
        regenerate: Bool
    ) async throws -> WordNormalization {
        let data = try await BackendAPI.post(
            path: "api/word-normalize",
            body: RequestBody(word: word, targetLanguage: targetLanguage, regenerate: regenerate)
        )
        // レスポンスは { input, lemma, status, reason, cached }。cached はデバッグ用で使わないため
        // Decodable が無視する。将来 status が増えても WordNormalizeStatus が .unknown に倒す。
        return try JSONDecoder().decode(WordNormalization.self, from: data)
    }
}
