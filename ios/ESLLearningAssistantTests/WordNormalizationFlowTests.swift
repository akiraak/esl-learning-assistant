import Foundation
import SwiftData
import Testing
@testable import ESLLearningAssistant

/// Add / タップ登録が共有する正規化判定 `WordNormalizationFlow.decide` と、UIテスト用スタブ
/// `WordNormalizeStub.parse` を、フェイクサービス差し替えで検証する。
@MainActor
struct WordNormalizationFlowTests {
    private func service(_ result: Result<WordNormalization, Error>) -> MockWordNormalizeService {
        let service = MockWordNormalizeService()
        service.result = result
        return service
    }

    private func normalization(
        _ status: WordNormalizeStatus,
        input: String,
        lemma: String,
        reason: String = ""
    ) -> WordNormalization {
        WordNormalization(input: input, lemma: lemma, status: status, reason: reason)
    }

    // MARK: - decide: 確認UIの出し分け

    @Test func inflectedRequestsConfirmation() async {
        let n = normalization(.inflected, input: "ran", lemma: "run", reason: "過去形")
        let decision = await WordNormalizationFlow.decide(input: "ran", targetLanguage: "ja", using: service(.success(n)))
        #expect(decision == .confirm(n))
    }

    @Test func misspelledRequestsConfirmation() async {
        let n = normalization(.misspelled, input: "recieve", lemma: "receive", reason: "綴り誤り")
        let decision = await WordNormalizationFlow.decide(input: "recieve", targetLanguage: "ja", using: service(.success(n)))
        #expect(decision == .confirm(n))
    }

    @Test func canonicalRegistersImmediately() async {
        let n = normalization(.canonical, input: "apple", lemma: "apple")
        let decision = await WordNormalizationFlow.decide(input: "apple", targetLanguage: "ja", using: service(.success(n)))
        #expect(decision == .registerImmediately(text: "apple"))
    }

    @Test func properNounPhraseUnknownRegisterImmediately() async {
        for status in [WordNormalizeStatus.properNoun, .phrase, .unknown] {
            let n = normalization(status, input: "Tokyo", lemma: "Tokyo")
            let decision = await WordNormalizationFlow.decide(input: "Tokyo", targetLanguage: "ja", using: service(.success(n)))
            #expect(decision == .registerImmediately(text: "Tokyo"))
        }
    }

    /// inflected でも lemma が入力と実質同じなら（訂正するものが無い）確認を出さず即登録
    @Test func inflectedButUnchangedLemmaRegistersImmediately() async {
        let n = normalization(.inflected, input: "run", lemma: "run")
        let decision = await WordNormalizationFlow.decide(input: "run", targetLanguage: "ja", using: service(.success(n)))
        #expect(decision == .registerImmediately(text: "run"))
    }

    // MARK: - decide: フォールバック

    /// 正規化サービスが失敗しても登録はブロックせず、入力のまま即登録へ倒す
    @Test func serviceFailureFallsBackToInput() async {
        let decision = await WordNormalizationFlow.decide(
            input: " ran ", targetLanguage: "ja", using: service(.failure(BackendAPIError.unauthorized))
        )
        // 入力はトリムして登録に回す
        #expect(decision == .registerImmediately(text: "ran"))
    }

    @Test func emptyInputRegistersImmediately() async {
        let called = MockWordNormalizeService()
        let decision = await WordNormalizationFlow.decide(input: "   ", targetLanguage: "ja", using: called)
        #expect(decision == .registerImmediately(text: ""))
        // 空入力ではサービスを呼ばない
        #expect(called.callCount == 0)
    }

    // MARK: - 正規化形が既存語 → 集約（WordRegistrar 再利用）

    /// 「ran」→「run」の確認で主ボタン（正規化形）を選んだとき、既存の「run」があれば
    /// 新規作成せず再利用され、単語が重複しない（集約）。
    @Test func registeringLemmaReusesExistingWord() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Class.self, Lesson.self, Photo.self, Word.self, WordOccurrence.self, AudioClip.self, Document.self,
            configurations: config
        )
        let context = ModelContext(container)
        let existing = Word(text: "run", translation: "走る")
        existing.aiInfoStatus = .completed
        context.insert(existing)
        try context.save()

        // 確認ダイアログ主ボタン相当: 正規化形 "run" で登録
        let result = WordRegistrar.register(
            text: "run",
            in: context,
            existingWords: try context.fetch(FetchDescriptor<Word>()),
            generateAIInfo: { _ in }
        )

        #expect(result?.isNew == false)
        #expect(result?.word.id == existing.id)
        #expect(try context.fetch(FetchDescriptor<Word>()).count == 1)
    }

    // MARK: - WordNormalizeStub.parse

    @Test func stubParsesPassthroughCanonical() {
        let n = WordNormalizeStub.parse("canonical", input: "apple")
        #expect(n.status == .canonical)
        #expect(n.lemma == "apple")
        #expect(n.reason == "")
        #expect(!n.requiresConfirmation)
    }

    @Test func stubParsesInflectedWithLemmaAndReason() {
        let n = WordNormalizeStub.parse("inflected|run|「ran」は「run」の過去形です", input: "ran")
        #expect(n.status == .inflected)
        #expect(n.lemma == "run")
        #expect(n.reason == "「ran」は「run」の過去形です")
        #expect(n.requiresConfirmation)
    }

    @Test func stubParsesMisspelledWithoutReason() {
        let n = WordNormalizeStub.parse("misspelled|receive", input: "recieve")
        #expect(n.status == .misspelled)
        #expect(n.lemma == "receive")
        #expect(n.reason == "")
        #expect(n.requiresConfirmation)
    }

    /// reason に "|" が含まれても後ろは全部 reason として扱う
    @Test func stubKeepsPipesInsideReason() {
        let n = WordNormalizeStub.parse("inflected|run|a|b", input: "ran")
        #expect(n.lemma == "run")
        #expect(n.reason == "a|b")
    }

    /// 訂正 status なのに lemma 省略なら入力語にフォールバック（＝確認不要になる）
    @Test func stubInflectedWithoutLemmaFallsBackToInput() {
        let n = WordNormalizeStub.parse("inflected", input: "ran")
        #expect(n.lemma == "ran")
        #expect(!n.requiresConfirmation)
    }

    @Test func stubUnknownStatusStringBecomesUnknown() {
        let n = WordNormalizeStub.parse("nonsense|x", input: "foo")
        #expect(n.status == .unknown)
        #expect(n.lemma == "foo")
    }
}
