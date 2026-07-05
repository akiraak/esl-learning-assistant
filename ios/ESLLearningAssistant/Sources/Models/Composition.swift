import Foundation
import SwiftData

/// 学習者の英作文とその AI 添削（docs/plans/writing-composition-feedback.md）。
/// Word と同様に Lesson に従属しない独立エンティティ。作文本文は端末ローカルが原則で、
/// サーバ側は保存しない（添削はログのみ）。
@Model
final class Composition {
    var id: UUID
    /// ユーザーが書いた英文
    var englishText: String
    /// ①の英文に対応する日本語（訳 or 日本語での説明＝伝えたかった意図）。
    /// 添削の方向を確定させるため AI に渡す。
    var japaneseText: String
    var createdAt: Date
    /// 下書き編集のたびに更新する。feedback.generatedAt との比較で「添削が古い」判定に使う。
    var updatedAt: Date
    /// 解説言語（実質 "ja"。生成時のユーザー母語設定を記録）
    var explanationLanguage: String
    /// 直近の添削結果（未添削 or 未生成なら nil）。埋め込み Codable。
    var feedback: WritingFeedback?

    init(
        id: UUID = UUID(),
        englishText: String = "",
        japaneseText: String = "",
        explanationLanguage: String,
        createdAt: Date = .now
    ) {
        self.id = id
        self.englishText = englishText
        self.japaneseText = japaneseText
        self.explanationLanguage = explanationLanguage
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.feedback = nil
    }
}

extension Composition {
    /// 本文（英文・日本語）が添削後に編集されているか。編集後は既存の添削を「古い」として扱う。
    /// feedback が無ければ false。
    var isFeedbackStale: Bool {
        guard let feedback else { return false }
        return feedback.generatedAt < updatedAt
    }

    /// 一覧に出すプレビュー用の1行テキスト（英文優先、空なら日本語）。
    var previewText: String {
        let english = englishText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !english.isEmpty { return english }
        return japaneseText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// バックエンド /api/writing-feedback のレスポンス feedback と同構造（backend/src/writingFeedback.ts）。
/// フィールドを増減する場合は両方を合わせること。
/// SwiftData の埋め込み Codable は実プロパティ名ベースで管理するため、CodingKeys は付けない
/// （リネームすると値が黙って未永続化になる。Word.swift の WordReviewState 参照）。
struct WritingFeedback: Codable {
    /// 修正後の英文（全文）
    var correctedText: String
    /// 解説言語での解説（どこをなぜ直したか）
    var explanation: String
    /// 生成に使ったモデル
    var model: String
    /// 生成日時（本文編集との前後比較で「添削が古い」判定に使う）
    var generatedAt: Date
}
