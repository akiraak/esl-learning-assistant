import Foundation

@MainActor
protocol WordIllustrationService {
    /// 単語イラスト（PNG）を取得する。サーバに保存済みならキャッシュ返却、無ければ生成される。
    /// regenerate: true でサーバキャッシュを無視して作りなおす。
    /// definition / exampleSentence: この見出しの英語定義・例文。同綴異義の兄弟見出しは
    /// サーバに word_info blob が無いため、作画プロンプト用にクライアントから直接渡す。
    func fetchIllustration(
        word: String,
        targetLanguage: String,
        senseIndex: Int,
        regenerate: Bool,
        definition: String?,
        exampleSentence: String?
    ) async throws -> Data
}

/// バックエンドの /api/word-illustration（GPT Image 2 中継）と通信し、単語イラストを取得する。
@MainActor
final class RemoteWordIllustrationService: WordIllustrationService {
    private struct RequestBody: Encodable {
        let word: String
        let targetLanguage: String
        let senseIndex: Int
        let regenerate: Bool
        let definition: String?
        let exampleSentence: String?
    }

    func fetchIllustration(
        word: String,
        targetLanguage: String,
        senseIndex: Int = 0,
        regenerate: Bool = false,
        definition: String? = nil,
        exampleSentence: String? = nil
    ) async throws -> Data {
        // サーバ側の画像生成は最大120秒（illustration.ts の REQUEST_TIMEOUT_MS）かかるため、
        // URLRequest 既定の60秒では生成完了前にiOS側だけタイムアウトしてしまう
        try await BackendAPI.post(
            path: "api/word-illustration",
            body: RequestBody(
                word: word,
                targetLanguage: targetLanguage,
                senseIndex: senseIndex,
                regenerate: regenerate,
                definition: definition,
                exampleSentence: exampleSentence
            ),
            timeout: 180
        )
    }
}
