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
    /// 旧データ（単発添削）の直近結果。v2 以降は書き込まず `rounds` を使う。
    /// ストアから外さないために残置（削除するとマイグレーションで開けなくなる恐れ）。未添削なら nil。
    var feedback: WritingFeedback?
    /// 改善のやり取りの履歴（古い順）。`rounds` computed の実ストレージ。
    /// マイグレーション安全のため必ず optional で追加する（swiftdata-codable-migration-pitfall）。
    var roundsStorage: [WritingRound]?

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
        self.roundsStorage = nil
    }
}

extension Composition {
    /// 改善の履歴（古い順）。`roundsStorage` が空でも旧データ（単一 `feedback`）があれば
    /// それを Round 1 として見せる（破壊的マイグレーション不要）。setter は storage を直接更新する。
    var rounds: [WritingRound] {
        get {
            if let roundsStorage, !roundsStorage.isEmpty { return roundsStorage }
            if let feedback {
                return [
                    WritingRound(
                        englishText: englishText,
                        japaneseText: japaneseText,
                        feedback: feedback,
                        createdAt: feedback.generatedAt
                    )
                ]
            }
            return []
        }
        set { roundsStorage = newValue }
    }

    /// 最新ラウンドの添削（未添削なら nil）
    var latestFeedback: WritingFeedback? { rounds.last?.feedback }

    /// 添削を1回以上受けているか
    var hasFeedback: Bool { !rounds.isEmpty }

    /// 現在の下書きが最終ラウンドと同一か（＝新たに送る変更が無い）。
    /// ラウンドがまだ無ければ false（初回は下書きさえあれば送れる）。
    var draftMatchesLastRound: Bool {
        guard let last = rounds.last else { return false }
        func norm(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }
        return norm(englishText) == norm(last.englishText)
            && norm(japaneseText) == norm(last.japaneseText)
    }

    /// 一覧に出すプレビュー用の1行テキスト（英文優先、空なら日本語）。
    var previewText: String {
        let english = englishText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !english.isEmpty { return english }
        return japaneseText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// 1回分の添削ラウンド（学習者が送った英文＋意図＋その添削）。改善のたびに `Composition.rounds` へ積む。
/// SwiftData 埋め込み Codable は実プロパティ名ベースで管理するため CodingKeys は付けない
/// （リネームすると値が黙って未永続化になる。WritingFeedback と同方針）。
struct WritingRound: Codable, Identifiable {
    var id: UUID
    /// このラウンドで学習者が送った英文
    var englishText: String
    /// このラウンドで学習者が送った日本語（伝えたかった意図）
    var japaneseText: String
    /// このラウンドの添削結果
    var feedback: WritingFeedback
    var createdAt: Date

    init(
        id: UUID = UUID(),
        englishText: String,
        japaneseText: String,
        feedback: WritingFeedback,
        createdAt: Date
    ) {
        self.id = id
        self.englishText = englishText
        self.japaneseText = japaneseText
        self.feedback = feedback
        self.createdAt = createdAt
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
