import Foundation
import SwiftData
import Testing
@testable import ESLLearningAssistant

/// サーバ保存済み単語のローカル取り込み（`WordSyncImporter`）の検証。
/// ネットワークは `StubWordListService`、台帳は専用 suite の `UserDefaults` に隔離し、
/// AI 情報生成は注入クロージャで観測する（課金・通信を起こさない）。
/// `WordSyncImporter.isRunning` の二重実行ガードが並列テストで干渉するため直列実行する。
@MainActor
@Suite(.serialized)
struct WordSyncImporterTests {
    @MainActor
    private final class StubWordListService: WordListService {
        var pages: [ServerWordListResponse]
        var error: Error?
        private(set) var requestedOffsets: [Int] = []

        init(pages: [ServerWordListResponse] = [], error: Error? = nil) {
            self.pages = pages
            self.error = error
        }

        func fetchWords(targetLanguage: String, limit: Int, offset: Int) async throws -> ServerWordListResponse {
            requestedOffsets.append(offset)
            if let error { throw error }
            guard let page = pages.first(where: { $0.offset == offset }) else {
                return ServerWordListResponse(total: 0, limit: limit, offset: offset, words: [])
            }
            return page
        }
    }

    private struct StubError: Error {}

    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Class.self, Lesson.self, Photo.self, Word.self, WordOccurrence.self, AudioClip.self, Document.self,
            configurations: config
        )
        return ModelContext(container)
    }

    /// テストごとに独立した UserDefaults（台帳の保存先）
    private func makeDefaults(_ suiteName: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func summary(_ word: String, targetLanguage: String = "ja") -> ServerWordSummary {
        ServerWordSummary(
            word: word,
            targetLanguage: targetLanguage,
            meaning: nil,
            partOfSpeech: nil,
            cefrLevel: nil,
            createdAt: "2026-08-01T00:00:00.000Z",
            updatedAt: "2026-08-01T00:00:00.000Z"
        )
    }

    private func page(_ words: [ServerWordSummary], total: Int? = nil, offset: Int = 0) -> ServerWordListResponse {
        ServerWordListResponse(
            total: total ?? words.count,
            limit: WordSyncImporter.pageLimit,
            offset: offset,
            words: words
        )
    }

    private func allWords(_ context: ModelContext) throws -> [Word] {
        try context.fetch(FetchDescriptor<Word>())
    }

    @Test func importsServerOnlyWords() async throws {
        let context = try makeContext()
        let defaults = makeDefaults("WordSyncImporterTests.import")
        let service = StubWordListService(pages: [page([summary("pick up"), summary("get around to")])])
        var generated: [String] = []

        let result = await WordSyncImporter.sync(
            modelContext: context,
            service: service,
            targetLanguage: "ja",
            defaults: defaults,
            generateAIInfo: { generated.append($0.text) }
        )

        #expect(result == WordSyncImporter.SyncResult(fetched: 2, imported: 2, skippedByLedger: 0, reusedExisting: 0, failed: false))
        #expect(try allWords(context).map(\.text).sorted() == ["get around to", "pick up"])
        // 熟語もそのまま登録され、AI 情報生成（サーバ生成済みならキャッシュヒット）が走る
        #expect(generated.sorted() == ["get around to", "pick up"])
        #expect(WordSyncImporter.importedKeys(defaults: defaults) == ["pick up|ja", "get around to|ja"])
    }

    @Test func doesNotDuplicateExistingLocalWordIgnoringCase() async throws {
        let context = try makeContext()
        let defaults = makeDefaults("WordSyncImporterTests.duplicate")
        let existing = Word(text: "Apple", translation: "りんご")
        existing.aiInfoStatus = .completed
        context.insert(existing)
        try context.save()
        let service = StubWordListService(pages: [page([summary("apple")])])
        var generated: [String] = []

        let result = await WordSyncImporter.sync(
            modelContext: context,
            service: service,
            targetLanguage: "ja",
            defaults: defaults,
            generateAIInfo: { generated.append($0.text) }
        )

        #expect(result.imported == 0)
        #expect(result.reusedExisting == 1)
        #expect(try allWords(context).count == 1)
        // AI 情報が既にある既存語は再生成しない
        #expect(generated.isEmpty)
        // 再利用でも台帳には載せる（以後スキップ）
        #expect(WordSyncImporter.importedKeys(defaults: defaults) == ["apple|ja"])
    }

    @Test func skipsWordsAlreadyInLedger() async throws {
        let context = try makeContext()
        let defaults = makeDefaults("WordSyncImporterTests.ledger")
        let service = StubWordListService(pages: [page([summary("apple")])])

        // 1回目: 取り込み → アプリ側で削除（ユーザーが不要と判断した想定）
        _ = await WordSyncImporter.sync(
            modelContext: context, service: service, targetLanguage: "ja", defaults: defaults, generateAIInfo: { _ in }
        )
        for word in try allWords(context) { context.delete(word) }
        try context.save()

        // 2回目: 台帳にあるので復活しない
        let result = await WordSyncImporter.sync(
            modelContext: context, service: service, targetLanguage: "ja", defaults: defaults, generateAIInfo: { _ in }
        )

        #expect(result == WordSyncImporter.SyncResult(fetched: 1, imported: 0, skippedByLedger: 1, reusedExisting: 0, failed: false))
        #expect(try allWords(context).isEmpty)
    }

    @Test func resetLedgerAllowsReimport() async throws {
        let context = try makeContext()
        let defaults = makeDefaults("WordSyncImporterTests.reset")
        let service = StubWordListService(pages: [page([summary("apple")])])

        _ = await WordSyncImporter.sync(
            modelContext: context, service: service, targetLanguage: "ja", defaults: defaults, generateAIInfo: { _ in }
        )
        for word in try allWords(context) { context.delete(word) }
        try context.save()
        WordSyncImporter.resetImportedKeys(defaults: defaults)

        let result = await WordSyncImporter.sync(
            modelContext: context, service: service, targetLanguage: "ja", defaults: defaults, generateAIInfo: { _ in }
        )

        #expect(result.imported == 1)
        #expect(try allWords(context).map(\.text) == ["apple"])
    }

    @Test func fetchFailureImportsNothingAndKeepsLedger() async throws {
        let context = try makeContext()
        let defaults = makeDefaults("WordSyncImporterTests.failure")
        let service = StubWordListService(pages: [page([summary("apple")])], error: StubError())

        let result = await WordSyncImporter.sync(
            modelContext: context, service: service, targetLanguage: "ja", defaults: defaults, generateAIInfo: { _ in }
        )

        #expect(result.failed)
        #expect(result.imported == 0)
        #expect(try allWords(context).isEmpty)
        #expect(WordSyncImporter.importedKeys(defaults: defaults).isEmpty)
    }

    @Test func emptyResponseImportsNothing() async throws {
        let context = try makeContext()
        let defaults = makeDefaults("WordSyncImporterTests.empty")
        let service = StubWordListService(pages: [page([])])

        let result = await WordSyncImporter.sync(
            modelContext: context, service: service, targetLanguage: "ja", defaults: defaults, generateAIInfo: { _ in }
        )

        #expect(result == WordSyncImporter.SyncResult())
        #expect(try allWords(context).isEmpty)
        #expect(WordSyncImporter.importedKeys(defaults: defaults).isEmpty)
    }

    @Test func fetchesNextPageUntilTotalIsReached() async throws {
        let context = try makeContext()
        let defaults = makeDefaults("WordSyncImporterTests.paging")
        let service = StubWordListService(pages: [
            page([summary("apple"), summary("banana")], total: 3, offset: 0),
            page([summary("cherry")], total: 3, offset: 2),
        ])

        let result = await WordSyncImporter.sync(
            modelContext: context, service: service, targetLanguage: "ja", defaults: defaults, generateAIInfo: { _ in }
        )

        #expect(service.requestedOffsets == [0, 2])
        #expect(result.fetched == 3)
        #expect(result.imported == 3)
        #expect(try allWords(context).map(\.text).sorted() == ["apple", "banana", "cherry"])
    }
}
