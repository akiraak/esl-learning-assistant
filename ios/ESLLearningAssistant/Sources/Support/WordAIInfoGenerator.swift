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
            // 主見出し（context に合う意味）を生成。ユーザー入力済みの訳語はヒントに使う。
            let primary = try await service.fetchWordInfo(
                word: word.text,
                targetLanguage: targetLanguage,
                context: context,
                userTranslation: word.translation.isEmpty ? nil : word.translation,
                regenerate: regenerate,
                senseHint: nil
            )
            apply(info: primary, to: word, targetLanguage: targetLanguage, senseGroupKey: nil)

            // 多義語の辞書式分割: 語源・意味が無関係な別見出し（同綴異義。fall=落ちる/秋 など）は
            // 見出しごとに個別生成し、別 Word エントリにする。各エントリは自分の意味専用の
            // 活用形・例文・発音・解説を持つ（詳細内容が完全に独立する）。
            var entries = [word]
            let others = primary.wordInfo.otherHomographs ?? []
            if let modelContext = word.modelContext, !others.isEmpty {
                for (offset, homograph) in others.enumerated() {
                    let groupKey = String(offset + 1)
                    let hint = "\(homograph.meaning)（\(homograph.partOfSpeech)）"
                    let siblingInfo: WordInfoResponse
                    do {
                        // 別見出しはサーバキャッシュ非対象（senseHint 付き）なので都度生成される
                        siblingInfo = try await service.fetchWordInfo(
                            word: word.text,
                            targetLanguage: targetLanguage,
                            context: nil,
                            userTranslation: nil,
                            regenerate: regenerate,
                            senseHint: hint
                        )
                    } catch {
                        // 別見出し1件の生成失敗は、主見出しの成功や他の見出しを妨げない
                        continue
                    }
                    let sibling = existingSibling(text: word.text, groupKey: groupKey, in: modelContext)
                        ?? insertSibling(text: word.text, groupKey: groupKey, in: modelContext)
                    apply(info: siblingInfo, to: sibling, targetLanguage: targetLanguage, senseGroupKey: groupKey)
                    entries.append(sibling)
                }
                // autosave任せだと直後にアプリを強制終了された場合に失われるため明示的に保存する
                modelContext.saveOrLog()
            }

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
            // イラストもテキスト情報の完成に続けてバックグラウンド生成する（詳細画面を開いていなくても走る）。
            // 見出しごとに1枚ずつ、その見出しの定義・例文を渡して生成する。
            //
            // regenerate: true で作りなおす。イラストのキーは (word, language, senseIndex) のみで
            // 語義内容を含まないため、削除→再登録した単語は古い語義の画像が残っていると再利用されて
            // しまう。AI情報を生成しなおしたこのタイミングで、必ず今の見出しの画像に更新する。
            for entry in entries {
                WordIllustrationGenerator.shared.generateIfNeeded(
                    word: entry.text,
                    targetLanguage: targetLanguage,
                    senseIndex: entry.illustrationSenseIndex,
                    regenerate: true,
                    definition: entry.illustrationDefinition,
                    exampleSentence: entry.illustrationExampleSentence
                )
            }
        } catch {
            word.aiInfoStatus = .failed
            word.aiInfoErrorMessage = error.localizedDescription
        }
    }

    /// 生成結果（1見出し分）を Word に反映する。senseGroupKey は主見出し=nil、兄弟見出し="1","2"…。
    private func apply(
        info response: WordInfoResponse,
        to word: Word,
        targetLanguage: String,
        senseGroupKey: String?
    ) {
        word.aiInfo = response.wordInfo
        word.aiInfoModel = response.model
        word.aiInfoLanguage = targetLanguage
        word.aiInfoGeneratedAt = .now
        word.aiInfoStatus = .completed
        word.senseGroupKey = senseGroupKey
        // 一覧表示用の訳語は先頭語義で自動補完する。ユーザーが入力・編集済みの訳語は上書きしない。
        if word.translation.isEmpty, let meaning = response.wordInfo.senses.first?.meaning {
            word.translation = meaning
        }
    }

    /// 既存の兄弟エントリ（同 text・同 senseGroupKey）を返す。再生成時は新規作成せず更新するため。
    private func existingSibling(text: String, groupKey: String, in context: ModelContext) -> Word? {
        let descriptor = FetchDescriptor<Word>(
            predicate: #Predicate { $0.text == text && $0.senseGroupKey == groupKey }
        )
        return (try? context.fetch(descriptor))?.first
    }

    /// 兄弟エントリを新規作成して挿入する（内容は後続の apply(info:) で埋める）。
    private func insertSibling(text: String, groupKey: String, in context: ModelContext) -> Word {
        let sibling = Word(text: text, translation: "")
        sibling.senseGroupKey = groupKey
        context.insert(sibling)
        return sibling
    }
}
