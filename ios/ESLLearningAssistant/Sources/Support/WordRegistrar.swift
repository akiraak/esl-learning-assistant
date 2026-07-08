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
    ///   - lesson: 指定時は出現記録を作って紐付ける。同一 word + sourcePhoto + sourceAudio の重複は作らない。
    ///   - sourcePhoto: 出現元の写真。AI生成にOCR本文を文脈として渡すために保持する。
    ///   - sourceAudio: 出現元の音声クリップ。AI生成に transcript を文脈として渡すために保持する（`sourcePhoto` の音声版）。
    ///   - sourceDocument: 出現元の文書。AI生成に抽出テキストを文脈として渡すために保持する（`sourceAudio` の文書版）。
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
        sourceAudio: AudioClip? = nil,
        sourceDocument: Document? = nil,
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
            link(word, to: lesson, sourcePhoto: sourcePhoto, sourceAudio: sourceAudio, sourceDocument: sourceDocument, in: modelContext)
        }

        // autosave任せだと直後にアプリを強制終了された場合に失われるため明示的に保存する
        modelContext.saveOrLog()

        // AI単語情報を未生成/失敗なら生成開始（バックグラウンドで継続）
        if word.aiInfoStatus == .none || word.aiInfoStatus == .failed {
            generateAIInfo(word)
        }

        return Result(word: word, isNew: isNew)
    }

    /// 出現記録を作ってレッスンに紐付ける。同一 word + sourcePhoto + sourceAudio + sourceDocument の
    /// 記録が既にあれば作らない（同じ写真・音声・文書内で同じ単語を複数回タップしても重複しない）。
    /// to-one側（occurrence.lesson）の設定だけだと逆側 lesson.wordOccurrences への反映と
    /// 変更通知が次の保存まで遅れるため、lesson側の配列にも明示的に追加する（関係の実体は同一）。
    @MainActor
    private static func link(
        _ word: Word,
        to lesson: Lesson,
        sourcePhoto: Photo?,
        sourceAudio: AudioClip?,
        sourceDocument: Document?,
        in modelContext: ModelContext
    ) {
        let alreadyLinked = word.occurrences.contains {
            $0.lesson.id == lesson.id
                && $0.sourcePhoto?.id == sourcePhoto?.id
                && $0.sourceAudio?.id == sourceAudio?.id
                && $0.sourceDocument?.id == sourceDocument?.id
        }
        guard !alreadyLinked else { return }
        let occurrence = WordOccurrence(word: word, lesson: lesson, sourcePhoto: sourcePhoto, sourceAudio: sourceAudio, sourceDocument: sourceDocument)
        modelContext.insert(occurrence)
        lesson.wordOccurrences.append(occurrence)
    }

    // MARK: - 登録後の手動編集（WordDetailView から使う）

    /// 単語詳細画面から手動でレッスンに紐付ける。OCR 由来ではないため `sourcePhoto = nil`。
    /// 重複は「そのレッスンに既に出現があるか」を `lesson.id` のみで判定して防ぐ
    /// （同一レッスンの行が二重に出ないように）。
    @MainActor
    static func linkManually(_ word: Word, to lesson: Lesson, in modelContext: ModelContext) {
        let alreadyLinked = word.occurrences.contains { $0.lesson.id == lesson.id }
        guard !alreadyLinked else { return }
        let occurrence = WordOccurrence(word: word, lesson: lesson, sourcePhoto: nil)
        modelContext.insert(occurrence)
        lesson.wordOccurrences.append(occurrence)
        modelContext.saveOrLog()
    }

    /// 出現記録を別レッスンへ付け替える。`sourcePhoto` は素性メタとして保持する。
    /// 付け替え先に既に同じ単語の出現があれば重複を作らず削除に倒す。
    @MainActor
    static func relink(_ occurrence: WordOccurrence, to lesson: Lesson, in modelContext: ModelContext) {
        guard occurrence.lesson.id != lesson.id else { return }
        if occurrence.word.occurrences.contains(where: { $0.lesson.id == lesson.id && $0.id != occurrence.id }) {
            // 付け替え先が既にリンク済み → 重複を作らずこの出現は削除する
            unlink(occurrence, in: modelContext)
            return
        }
        occurrence.lesson = lesson
        lesson.wordOccurrences.append(occurrence)
        modelContext.saveOrLog()
    }

    /// 出現記録のみを削除してレッスンとの紐付けを解除する（`Word` 本体・`Lesson` は残る）。
    @MainActor
    static func unlink(_ occurrence: WordOccurrence, in modelContext: ModelContext) {
        modelContext.delete(occurrence)
        modelContext.saveOrLog()
    }

    // MARK: - 登録済み単語の訂正（原形化・綴り訂正の後追い。WordDetailView から使う）

    /// `correct(_:to:...)` の結果。
    enum CorrectionOutcome {
        /// 衝突が無く、同じ `Word` 行の `text` を差し替えた（reviewState・occurrences は保持）。
        case renamedInPlace(Word)
        /// 正規化形が既存の別 `Word` と衝突したため、出現を既存語へ集約して元の行を削除した。
        /// 付随する値は集約先（生き残った既存語）。
        case mergedInto(Word)

        /// 遷移・表示に使う対象単語（リネーム後の同一行、またはマージ先の既存語）。
        var word: Word {
            switch self {
            case .renamedInPlace(let word), .mergedInto(let word): return word
            }
        }
    }

    /// 登録済みの `word` を見出し語 `lemma`（原形／正しい綴り）へ訂正する。
    ///
    /// `Word.text` はイラスト・クイズ・音声・backend の各キャッシュキーだが、いずれも
    /// 新しい `text` を引き直すと自然にミス→再生成されるため、旧キーの生成物は放置でよい
    /// （移行不要。詳細は docs/plans/word-input-normalization.md Phase 4）。この関数は SwiftData 側
    /// （行の値・出現の付け替え・重複解消）だけを担う。
    ///
    /// - Parameters:
    ///   - existingWords: 衝突判定に使う全単語（`allWords`）。
    ///   - regenerateAIInfo: リネーム後に AI 情報を作り直すトリガ。テストで差し替え可能にするため注入する。
    /// - Returns: 訂正結果。`lemma` が空、または現在の `text` と完全一致で訂正不要なら nil。
    @MainActor
    @discardableResult
    static func correct(
        _ word: Word,
        to lemma: String,
        in modelContext: ModelContext,
        existingWords: [Word],
        regenerateAIInfo: (Word) -> Void = { WordAIInfoGenerator.shared.generateInBackground(for: $0) }
    ) -> CorrectionOutcome? {
        let newText = lemma.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newText.isEmpty else { return nil }
        // 完全一致は訂正不要
        guard newText != word.text else { return nil }

        // 大小のみの違い（例: "Apple"→"apple"）は派生情報・キャッシュキー（小文字化済み）とも
        // 同一なので、綴り（表示）だけ整えて派生情報は保持する（再生成しない）。
        if newText.compare(word.text, options: [.caseInsensitive]) == .orderedSame {
            word.text = newText
            modelContext.saveOrLog()
            return .renamedInPlace(word)
        }

        // 衝突: 自分以外の既存語が新しい綴りと大小無視で一致 → 出現を集約して元の行を削除
        if let survivor = existingWords.first(where: {
            $0.id != word.id && $0.text.compare(newText, options: [.caseInsensitive]) == .orderedSame
        }) {
            mergeOccurrences(from: word, into: survivor, in: modelContext)
            // 残った出現（付け替え済み）は survivor を指すため cascade で消えない。元の行だけ削除する。
            modelContext.delete(word)
            modelContext.saveOrLog()
            return .mergedInto(survivor)
        }

        // 衝突なし: その場でリネームし、旧綴り由来の派生情報を捨てて作り直す
        word.text = newText
        resetDerivedInfo(word)
        modelContext.saveOrLog()
        // 新しい見出し語の AI 情報を生成（サーバキャッシュにあれば再利用）。成功時にクイズ・イラストも連鎖生成される
        regenerateAIInfo(word)
        return .renamedInPlace(word)
    }

    /// `source` の出現をすべて `survivor` へ付け替える。`survivor` に既に同一
    /// (lesson, sourcePhoto, sourceAudio, sourceDocument) の出現があれば重複を作らず捨てる
    /// （`link` と同じ dedup ルール）。
    /// `reviewState`・`aiInfo`・`translation` などの行の値は既存語（`survivor`）のものを維持する。
    @MainActor
    private static func mergeOccurrences(from source: Word, into survivor: Word, in modelContext: ModelContext) {
        // 付け替えで source.occurrences が変化するため、スナップショットを走査する
        for occurrence in Array(source.occurrences) {
            let duplicate = survivor.occurrences.contains {
                $0.lesson.id == occurrence.lesson.id
                    && $0.sourcePhoto?.id == occurrence.sourcePhoto?.id
                    && $0.sourceAudio?.id == occurrence.sourceAudio?.id
                    && $0.sourceDocument?.id == occurrence.sourceDocument?.id
            }
            if duplicate {
                modelContext.delete(occurrence)
            } else {
                // to-one を付け替え、逆側配列にも明示追加して即時反映させる（`relink` と同じ作法）
                occurrence.word = survivor
                survivor.occurrences.append(occurrence)
            }
        }
    }

    /// 旧綴り由来の派生情報を消して AI 生成前の状態に戻す。`translation` は空でないと
    /// `WordAIInfoGenerator` が上書きしないため必ずクリアする。reviewState と occurrences は
    /// 語の同一性に属するため保持する（リネームは同じ学習対象の綴り訂正）。
    @MainActor
    private static func resetDerivedInfo(_ word: Word) {
        word.translation = ""
        word.partOfSpeech = nil
        word.grammarNote = nil
        word.exampleSentence = nil
        word.exampleSentenceSource = nil
        word.aiInfo = nil
        word.aiInfoStatus = .none
        word.aiInfoErrorMessage = nil
        word.aiInfoGeneratedAt = nil
        word.aiInfoModel = nil
        word.aiInfoLanguage = nil
    }
}
