import Foundation

/// 単語登録前の正規化（原形化・綴り訂正）の判定を、Add Word フォームと英文タップ登録で共有する。
/// 「入力語を正規化し、確認UIを出すか即登録かを決める」までを担い、実際の登録は WordRegistrar が行う。
@MainActor
enum WordNormalizationFlow {
    /// Add / タップ押下時の判定結果。
    enum Decision: Equatable {
        /// 確認不要。このテキストで即登録してよい。
        /// - canonical / 固有名詞 / 連語 / 判定不能（訂正しない status）
        /// - 正規化サービス失敗時のフォールバック（入力のまま）
        case registerImmediately(text: String)
        /// 訂正候補あり。確認UI（主=正規化形 / 逃げ道=入力形 / Cancel）を出す。
        case confirm(WordNormalization)
    }

    /// 現在の母語（言語コード）。未設定なら既定値。WordAIInfoGenerator と同じ読み方。
    static var targetLanguage: String {
        UserDefaults.standard.string(forKey: AppSettingsKeys.targetLanguageCode)
            ?? AppSettingsKeys.defaultTargetLanguageCode
    }

    /// 入力語を正規化し、確認UIを出すか即登録かを決める。
    /// サービス失敗（オフライン等）時は登録をブロックせず、入力のまま即登録へフォールバックする。
    static func decide(
        input: String,
        targetLanguage: String,
        using service: any WordNormalizeService
    ) async -> Decision {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .registerImmediately(text: trimmed) }

        guard let normalization = try? await service.normalize(word: trimmed, targetLanguage: targetLanguage) else {
            // 正規化に失敗しても登録は止めない（従来どおり入力のまま登録する）
            return .registerImmediately(text: trimmed)
        }
        return normalization.requiresConfirmation
            ? .confirm(normalization)
            : .registerImmediately(text: trimmed)
    }
}
