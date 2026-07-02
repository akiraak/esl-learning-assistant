import Foundation

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
            word.aiInfo = response.wordInfo
            word.aiInfoModel = response.model
            word.aiInfoLanguage = targetLanguage
            word.aiInfoGeneratedAt = .now
            word.aiInfoStatus = .completed
            // 単語登録は見出し語のみのため、一覧表示用の訳語は先頭の語義（文脈に合う語義）で自動補完する。
            // ユーザーが入力・編集済みの訳語は上書きしない。
            if word.translation.isEmpty, let firstMeaning = response.wordInfo.senses.first?.meaning {
                word.translation = firstMeaning
            }
        } catch {
            word.aiInfoStatus = .failed
            word.aiInfoErrorMessage = error.localizedDescription
        }
    }
}
