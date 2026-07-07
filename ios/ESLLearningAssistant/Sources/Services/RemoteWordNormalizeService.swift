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
        // UIテスト用スタブが設定されていれば実ネットワークを介さず決定的な結果を返す
        // （YouTubeOEmbed と同じ流儀。確認UIの出し分けを E2E で決定的にする）。
        if let stub = WordNormalizeStub.fromDefaults(input: word) {
            return stub
        }
        let data = try await BackendAPI.post(
            path: "api/word-normalize",
            body: RequestBody(word: word, targetLanguage: targetLanguage, regenerate: regenerate)
        )
        // レスポンスは { input, lemma, status, reason, cached }。cached はデバッグ用で使わないため
        // Decodable が無視する。将来 status が増えても WordNormalizeStatus が .unknown に倒す。
        return try JSONDecoder().decode(WordNormalization.self, from: data)
    }
}

/// UIテスト用の正規化スタブ。`-uiTestStubWordNormalize "<status>|<lemma>|<reason>"` の launch 引数で設定する
/// （iOS が引数を UserDefaults へ写す）。非設定なら nil を返し実ネットワークを使う。
///
/// 例:
///   "canonical"                              → 訂正しない（lemma=入力）。既存 UI テストの素通し用。
///   "inflected|run|「ran」は「run」の過去形です"  → 確認UIを出す（原形 run を提案）。
enum WordNormalizeStub {
    static let defaultsKey = "uiTestStubWordNormalize"

    static func fromDefaults(input: String, defaults: UserDefaults = .standard) -> WordNormalization? {
        guard let spec = defaults.string(forKey: defaultsKey), !spec.isEmpty else { return nil }
        return parse(spec, input: input)
    }

    /// "<status>|<lemma>|<reason>" を解釈する（lemma/reason は省略可・純関数でテスト対象）。
    /// 訂正しない status（canonical/proper_noun/phrase/unknown）では lemma=入力・reason="" に正規化し、
    /// 未知の status 文字列は .unknown に倒す。
    static func parse(_ spec: String, input: String) -> WordNormalization {
        let parts = spec.components(separatedBy: "|")
        let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let status = WordNormalizeStatus(rawValue: parts[0].trimmingCharacters(in: .whitespaces)) ?? .unknown
        guard status.suggestsCorrection else {
            return WordNormalization(input: trimmedInput, lemma: trimmedInput, status: status, reason: "")
        }
        let lemma = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : trimmedInput
        let reason = parts.count > 2 ? parts[2...].joined(separator: "|") : ""
        return WordNormalization(input: trimmedInput, lemma: lemma, status: status, reason: reason)
    }
}
