import Foundation
import SwiftData
import os

/// サーバ（`GET /api/words`）に保存済みの単語を、ローカルの `Word` へ差分取り込みする。
///
/// 外部アプリが API 経由で保存した単語はサーバにしか無く、アプリの単語一覧はローカル
/// SwiftData を引くだけなので表示されない（docs/plans/external-word-registration-sync.md）。
/// この取り込みが唯一の「サーバ→アプリ」経路になる。
///
/// - 取得: 全件をページングで取得して差分判定する（`updatedSince` カーソルは使わない。
///   管理画面での再生成で `updated_at` が動くと、アプリで削除した語が復活してしまうため）。
/// - 取り込み: `WordRegistrar.register` に委譲するので、同綴りの重複排除・AI 情報生成
///   （サーバ保存済みならキャッシュヒットで即完了）・クイズ/イラストの連鎖生成がそのまま効く。
/// - 台帳: 取り込んだキーを `UserDefaults` に残し、アプリ側で削除した語が復活しないようにする。
@MainActor
enum WordSyncImporter {
    /// 1リクエストあたりの取得件数（サーバの上限 `WORD_LIST_LIMIT_MAX` と同じ）
    static let pageLimit = 500
    /// ページング暴走の保険。500語 × 20 = 10,000語まで
    private static let maxPages = 20

    /// 起動時同期と pull-to-refresh の同時実行を防ぐ（二重取り込みは
    /// `WordRegistrar` が弾くが、AI 生成を無駄に走らせないため）
    private static var isRunning = false

    struct SyncResult: Equatable {
        /// サーバから取得できた語数
        var fetched = 0
        /// 新規に `Word` を作った数
        var imported = 0
        /// 台帳にあってスキップした数
        var skippedByLedger = 0
        /// 同綴りのローカル単語が既にあり再利用した数
        var reusedExisting = 0
        /// 取得に失敗した（この場合は何も取り込まず台帳も進めない）
        var failed = false
    }

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "ESLLearningAssistant",
        category: "WordSyncImporter"
    )

    /// サーバの単語をローカルへ取り込む。失敗はログに残すだけで throw しない
    /// （オフラインでも一覧表示を妨げないため）。
    /// - Parameters:
    ///   - generateAIInfo: 取り込んだ語の AI 情報生成。**逐次 await** して一気に走らせない
    ///     （まとめて数百語が来ても課金が急増しないように）。テストで差し替えられるよう注入する。
    @discardableResult
    static func sync(
        modelContext: ModelContext,
        service: WordListService = RemoteWordListService(),
        targetLanguage: String = UserDefaults.standard.string(forKey: AppSettingsKeys.targetLanguageCode)
            ?? AppSettingsKeys.defaultTargetLanguageCode,
        defaults: UserDefaults = .standard,
        generateAIInfo: (Word) async -> Void = { await WordAIInfoGenerator.shared.generate(for: $0) }
    ) async -> SyncResult {
        guard !isRunning else { return SyncResult() }
        isRunning = true
        defer { isRunning = false }

        var result = SyncResult()

        guard let serverWords = await fetchAll(service: service, targetLanguage: targetLanguage) else {
            result.failed = true
            return result
        }
        result.fetched = serverWords.count
        guard !serverWords.isEmpty else { return result }

        var ledger = importedKeys(defaults: defaults)
        var existingWords = (try? modelContext.fetch(FetchDescriptor<Word>())) ?? []

        for serverWord in serverWords {
            let key = ledgerKey(word: serverWord.word, targetLanguage: serverWord.targetLanguage)
            guard !ledger.contains(key) else {
                result.skippedByLedger += 1
                continue
            }

            // register は同期関数なので、生成対象を受け取ってからこのループ内で逐次 await する
            var wordNeedingAIInfo: Word?
            let registered = WordRegistrar.register(
                text: serverWord.word,
                in: modelContext,
                existingWords: existingWords,
                lesson: nil,
                generateAIInfo: { wordNeedingAIInfo = $0 }
            )
            guard let registered else { continue }

            if registered.isNew {
                result.imported += 1
                existingWords.append(registered.word)
            } else {
                result.reusedExisting += 1
            }

            ledger.insert(key)
            // 途中で終了しても取り込み済みが失われないよう1語ごとに保存する（件数は小さい）
            save(keys: ledger, defaults: defaults)

            if let wordNeedingAIInfo {
                await generateAIInfo(wordNeedingAIInfo)
            }
        }

        logger.info(
            """
            sync done: fetched=\(result.fetched, privacy: .public) \
            imported=\(result.imported, privacy: .public) \
            reused=\(result.reusedExisting, privacy: .public) \
            skipped=\(result.skippedByLedger, privacy: .public)
            """
        )
        return result
    }

    /// 全ページを取得して連結する。1ページでも失敗したら nil（部分取り込みで台帳を進めない）
    private static func fetchAll(service: WordListService, targetLanguage: String) async -> [ServerWordSummary]? {
        var collected: [ServerWordSummary] = []
        var offset = 0
        for _ in 0..<maxPages {
            let response: ServerWordListResponse
            do {
                response = try await service.fetchWords(targetLanguage: targetLanguage, limit: pageLimit, offset: offset)
            } catch {
                logger.error("fetch failed at offset \(offset, privacy: .public): \(error.localizedDescription, privacy: .public)")
                return nil
            }
            collected.append(contentsOf: response.words)
            // 空ページ（終端）か、総数に達したら終わり
            if response.words.isEmpty || collected.count >= response.total { return collected }
            offset += response.words.count
        }
        logger.error("fetch stopped at page limit (\(maxPages, privacy: .public) pages)")
        return collected
    }

    // MARK: - 取り込み済み台帳

    /// 台帳キー。サーバの `word` は正規化済みだが、念のためこちら側でも trim + 小文字化する
    static func ledgerKey(word: String, targetLanguage: String) -> String {
        "\(WordRegistrar.normalizeSpacing(word).lowercased())|\(targetLanguage.lowercased())"
    }

    static func importedKeys(defaults: UserDefaults = .standard) -> Set<String> {
        Set(defaults.stringArray(forKey: AppSettingsKeys.importedServerWordKeys) ?? [])
    }

    /// 台帳を空にする（設定画面の「取り込み済みをリセット」）。次の同期で全件を取り込み直す
    static func resetImportedKeys(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: AppSettingsKeys.importedServerWordKeys)
    }

    private static func save(keys: Set<String>, defaults: UserDefaults) {
        defaults.set(keys.sorted(), forKey: AppSettingsKeys.importedServerWordKeys)
    }
}
