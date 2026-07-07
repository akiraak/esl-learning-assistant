import Foundation
import Testing
@testable import ESLLearningAssistant

/// WordNormalization のデコード（/api/word-normalize の実レスポンス形）と、
/// 確認UIの出し分けに使う派生プロパティを検証する。
struct WordNormalizationTests {
    private func decode(_ json: String) throws -> WordNormalization {
        let data = try #require(json.data(using: .utf8))
        return try JSONDecoder().decode(WordNormalization.self, from: data)
    }

    // MARK: - デコード（各 status）

    @Test func decodesInflectedResponse() throws {
        let n = try decode("""
        { "input": "ran", "lemma": "run", "status": "inflected",
          "reason": "「ran」は動詞「run」の過去形です", "cached": false }
        """)
        #expect(n.input == "ran")
        #expect(n.lemma == "run")
        #expect(n.status == .inflected)
        #expect(n.reason == "「ran」は動詞「run」の過去形です")
        #expect(n.requiresConfirmation)
    }

    @Test func decodesMisspelledResponse() throws {
        let n = try decode("""
        { "input": "recieve", "lemma": "receive", "status": "misspelled",
          "reason": "綴りの誤りです", "cached": true }
        """)
        #expect(n.status == .misspelled)
        #expect(n.lemma == "receive")
        #expect(n.requiresConfirmation)
    }

    @Test func canonicalDoesNotRequireConfirmation() throws {
        let n = try decode(#"{ "input": "apple", "lemma": "apple", "status": "canonical", "reason": "", "cached": false }"#)
        #expect(n.status == .canonical)
        #expect(!n.requiresConfirmation)
    }

    /// status の proper_noun（スネークケース）が properNoun に対応すること
    @Test func decodesProperNounSnakeCase() throws {
        let n = try decode(#"{ "input": "Tokyo", "lemma": "Tokyo", "status": "proper_noun", "reason": "" }"#)
        #expect(n.status == .properNoun)
        #expect(!n.requiresConfirmation)
    }

    @Test func phraseAndUnknownDoNotRequireConfirmation() throws {
        let phrase = try decode(#"{ "input": "look up", "lemma": "look up", "status": "phrase", "reason": "" }"#)
        #expect(phrase.status == .phrase)
        #expect(!phrase.requiresConfirmation)

        let unknown = try decode(#"{ "input": "asdfg", "lemma": "asdfg", "status": "unknown", "reason": "" }"#)
        #expect(unknown.status == .unknown)
        #expect(!unknown.requiresConfirmation)
    }

    /// 将来サーバが未知の status を返しても .unknown に倒して安全側（訂正しない）に扱う
    @Test func unknownStatusValueFallsBackToUnknown() throws {
        let n = try decode(#"{ "input": "x", "lemma": "x", "status": "brand_new_status", "reason": "" }"#)
        #expect(n.status == .unknown)
        #expect(!n.requiresConfirmation)
    }

    // MARK: - requiresConfirmation の境界

    /// status が訂正提案でも lemma が入力と（大小の違いだけで）実質同じなら確認を出さない
    @Test func noConfirmationWhenLemmaMatchesInputIgnoringCase() throws {
        let n = try decode(#"{ "input": "Run", "lemma": "run", "status": "inflected", "reason": "" }"#)
        #expect(!n.requiresConfirmation)
    }

    // MARK: - effectiveLemma

    @Test func effectiveLemmaFallsBackToInputWhenEmpty() throws {
        let n = try decode(#"{ "input": "  apple  ", "lemma": "  ", "status": "canonical", "reason": "" }"#)
        #expect(n.effectiveLemma == "apple")
    }

    @Test func effectiveLemmaTrimsWhitespace() throws {
        let n = try decode(#"{ "input": "ran", "lemma": " run ", "status": "inflected", "reason": "" }"#)
        #expect(n.effectiveLemma == "run")
    }

    // MARK: - status の派生プロパティ

    @Test func suggestsCorrectionMatchesStatus() {
        #expect(WordNormalizeStatus.inflected.suggestsCorrection)
        #expect(WordNormalizeStatus.misspelled.suggestsCorrection)
        #expect(!WordNormalizeStatus.canonical.suggestsCorrection)
        #expect(!WordNormalizeStatus.properNoun.suggestsCorrection)
        #expect(!WordNormalizeStatus.phrase.suggestsCorrection)
        #expect(!WordNormalizeStatus.unknown.suggestsCorrection)
    }
}
