import Foundation
import SwiftData

/// 単語のAI生成情報の取得と、Word の aiInfo / aiInfoStatus 更新を担う。
/// 画面が閉じてもバックグラウンドで生成を継続できるよう、共有インスタンスを使う。
@MainActor
final class WordAIInfoGenerator {
    static let shared = WordAIInfoGenerator()

    private let service: WordInfoService

    init(service: WordInfoService = RemoteWordInfoService()) {
        self.service = service
    }

    /// 生成を開始してすぐ戻る（WordAddView の登録時トリガー用）。
    /// regenerate: true でサーバ保存済みの内容も作りなおす（省略時はサーバ保存があればそれを受け取る）。
    func generateInBackground(for word: Word, regenerate: Bool = false) {
        Task { await generate(for: word, regenerate: regenerate) }
    }

    /// 単語情報を生成して word に反映する。生成中の単語には多重実行しない。
    func generate(for word: Word, regenerate: Bool = false) async {
        guard word.aiInfoStatus != .generating else { return }
        word.aiInfoStatus = .generating
        word.aiInfoErrorMessage = nil

        let targetLanguage = UserDefaults.standard.string(forKey: AppSettingsKeys.targetLanguageCode)
            ?? AppSettingsKeys.defaultTargetLanguageCode
        // 単語が登場した教科書本文（OCR結果）を文脈として渡す。
        // 手動登録のみの単語は sourcePhoto が無く nil になる（文脈なし生成）。
        let context = word.occurrences
            .sorted { $0.occurredAt > $1.occurredAt }
            .compactMap { $0.sourcePhoto?.ocrText }
            .first { !$0.isEmpty }

        do {
            let response = try await service.fetchWordInfo(
                word: word.text,
                targetLanguage: targetLanguage,
                context: context,
                userTranslation: word.translation.isEmpty ? nil : word.translation,
                regenerate: regenerate
            )
            // 多義語の辞書式分割: 同綴異義（fall=落ちる/秋 など）は別 Word エントリに分ける。
            // 文脈に合うグループ0を渡された word に反映し、追加グループは兄弟 Word として作る。
            let entries = applySplit(response: response, to: word, targetLanguage: targetLanguage)

            // 復習クイズ問題をサーバで事前生成しておく（保存はサーバ側。fire-and-forget で、
            // 失敗しても単語情報の成功表示には影響させない。未生成のままでも復習セッション
            // 開始時の自己修復トリガで再度生成がかかる）。
            // NOTE: クイズはまだ語義非分離（word text 単位）。語義ごと分離は Phase 2。
            let wordText = word.text
            Task.detached {
                try? await RemoteQuizQuestionService().triggerGeneration(
                    word: wordText, targetLanguage: targetLanguage, regenerate: regenerate
                )
            }
            // イラストもテキスト情報の完成に続けてバックグラウンド生成しておく（詳細画面を
            // 開いていなくても走る）。失敗しても単語情報の成功表示には影響させず、詳細画面の
            // イラスト行から Retry できる。分割後は各エントリの語義ごとに1枚ずつ生成する。
            //
            // regenerate: true で作りなおす。イラストのキーは (word, language, senseIndex) のみで
            // 語義内容を含まないため、削除→再登録した単語は古い語義の画像が残っていると再利用されて
            // しまう。AI情報を生成しなおしたこのタイミングで、必ず今の語義の画像に更新する。
            for entry in entries {
                WordIllustrationGenerator.shared.generateIfNeeded(
                    word: entry.text,
                    targetLanguage: targetLanguage,
                    senseIndex: entry.illustrationSenseIndex,
                    regenerate: true
                )
            }
        } catch {
            word.aiInfoStatus = .failed
            word.aiInfoErrorMessage = error.localizedDescription
        }
    }

    /// AI応答の senses を homographGroup で見出し分割し、Word エントリ群に反映する。
    /// 文脈に合う先頭グループを渡された `word` に、追加グループを兄弟 Word として作成し、
    /// 反映した全エントリ（base + 兄弟）を返す（呼び出し側がイラスト生成に使う）。
    private func applySplit(
        response: WordInfoResponse,
        to word: Word,
        targetLanguage: String
    ) -> [Word] {
        let senses = response.wordInfo.senses
        // グループ番号を出現順に列挙（senses[0] のグループ = 文脈に合う先頭グループ）
        var groupsInOrder: [Int] = []
        for sense in senses {
            let group = sense.homographGroup ?? 0
            if !groupsInOrder.contains(group) { groupsInOrder.append(group) }
        }
        let primaryGroup = groupsInOrder.first ?? 0
        let didSplit = groupsInOrder.count > 1

        func firstMeaning(of group: Int) -> String? {
            senses.first { ($0.homographGroup ?? 0) == group }?.meaning
        }

        // base（渡された word）に先頭グループを反映
        word.aiInfo = response.wordInfo
        word.aiInfoModel = response.model
        word.aiInfoLanguage = targetLanguage
        word.aiInfoGeneratedAt = .now
        word.aiInfoStatus = .completed
        word.senseGroupKey = didSplit ? String(primaryGroup) : nil
        // 一覧表示用の訳語は担当グループの先頭語義で自動補完する。
        // ユーザーが入力・編集済みの訳語は上書きしない。
        if word.translation.isEmpty, let meaning = firstMeaning(of: primaryGroup) {
            word.translation = meaning
        }

        var entries = [word]
        // 兄弟 Word はモデルに挿入済みでないと作れない（全呼び出し元は挿入済み word を渡す）
        guard didSplit, let context = word.modelContext else { return entries }

        // 既存の兄弟（同 text・同 senseGroupKey）を重複生成しないための照合セット。
        // 再生成や「同じ単語を再追加」で二重に増えるのを防ぐ。
        let wordText = word.text
        let descriptor = FetchDescriptor<Word>(predicate: #Predicate { $0.text == wordText })
        let existingKeys = Set(
            ((try? context.fetch(descriptor)) ?? []).compactMap(\.senseGroupKey)
        )

        for group in groupsInOrder where group != primaryGroup {
            let key = String(group)
            if existingKeys.contains(key) { continue }
            let sibling = Word(text: word.text, translation: firstMeaning(of: group) ?? "")
            sibling.aiInfo = response.wordInfo
            sibling.aiInfoModel = response.model
            sibling.aiInfoLanguage = targetLanguage
            sibling.aiInfoGeneratedAt = .now
            sibling.aiInfoStatus = .completed
            sibling.senseGroupKey = key
            context.insert(sibling)
            entries.append(sibling)
        }
        // autosave任せだと直後にアプリを強制終了された場合に失われるため明示的に保存する
        context.saveOrLog()
        return entries
    }
}
