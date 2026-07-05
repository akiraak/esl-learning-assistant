import Foundation
import SwiftData

/// 単語登録ロジックの共通化。`WordAddView` のフォーム追加と、英文タップ登録の両方が使う。
/// 同綴りの既存単語があれば再利用し、無ければ新規作成する。レッスン指定時は出現記録
/// （`WordOccurrence`）を紐付け、未生成なら AI 情報生成をトリガする。
enum WordRegistrar {
    struct Result {
        let word: Word
        /// 新規作成なら true、既存単語の再利用なら false
        let isNew: Bool
    }

    /// 単語を登録（再利用 or 新規作成）する。
    /// - Parameters:
    ///   - lesson: 指定時は出現記録を作って紐付ける。同一 word + sourcePhoto の重複は作らない。
    ///   - sourcePhoto: 出現元の写真。AI生成にOCR本文を文脈として渡すために保持する。
    ///   - generateAIInfo: 未生成/失敗時に呼ぶAI生成トリガ。テストで差し替え可能にするため注入する。
    /// - Returns: 登録結果。text が空なら nil。
    @MainActor
    @discardableResult
    static func register(
        text rawText: String,
        in modelContext: ModelContext,
        existingWords: [Word],
        lesson: Lesson? = nil,
        sourcePhoto: Photo? = nil,
        generateAIInfo: (Word) -> Void = { WordAIInfoGenerator.shared.generateInBackground(for: $0) }
    ) -> Result? {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        let word: Word
        let isNew: Bool
        if let existing = existingWords.first(where: {
            $0.text.compare(text, options: [.caseInsensitive]) == .orderedSame
        }) {
            word = existing
            isNew = false
        } else {
            // 訳語はAI生成の完了時に自動補完される（WordAIInfoGenerator）
            word = Word(text: text, translation: "")
            modelContext.insert(word)
            isNew = true
        }

        if let lesson {
            link(word, to: lesson, sourcePhoto: sourcePhoto, in: modelContext)
        }

        // autosave任せだと直後にアプリを強制終了された場合に失われるため明示的に保存する
        modelContext.saveOrLog()

        // AI単語情報を未生成/失敗なら生成開始（バックグラウンドで継続）
        if word.aiInfoStatus == .none || word.aiInfoStatus == .failed {
            generateAIInfo(word)
        }

        return Result(word: word, isNew: isNew)
    }

    /// 出現記録を作ってレッスンに紐付ける。同一 word + sourcePhoto の記録が既にあれば作らない
    /// （同じ写真内で同じ単語を複数回タップしても重複しない）。
    /// to-one側（occurrence.lesson）の設定だけだと逆側 lesson.wordOccurrences への反映と
    /// 変更通知が次の保存まで遅れるため、lesson側の配列にも明示的に追加する（関係の実体は同一）。
    @MainActor
    private static func link(
        _ word: Word,
        to lesson: Lesson,
        sourcePhoto: Photo?,
        in modelContext: ModelContext
    ) {
        let alreadyLinked = word.occurrences.contains {
            $0.lesson.id == lesson.id && $0.sourcePhoto?.id == sourcePhoto?.id
        }
        guard !alreadyLinked else { return }
        let occurrence = WordOccurrence(word: word, lesson: lesson, sourcePhoto: sourcePhoto)
        modelContext.insert(occurrence)
        lesson.wordOccurrences.append(occurrence)
    }
}
