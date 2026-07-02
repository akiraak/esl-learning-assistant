import Foundation
import SwiftData

@Model
final class Word {
    var id: UUID
    var text: String
    var translation: String
    var exampleSentence: String?
    var exampleSentenceSource: ExampleSentenceSource?
    var partOfSpeech: String?
    var grammarNote: String?
    var registeredAt: Date
    var reviewState: WordReviewState

    // AI生成情報（docs/plans/word-ai-info-generation.md）。
    // すべてoptional/デフォルトありにして既存データの軽量マイグレーションを維持する。
    var aiInfo: WordAIInfo?
    var aiInfoStatus: WordAIInfoStatus = WordAIInfoStatus.none
    var aiInfoGeneratedAt: Date?
    var aiInfoModel: String?
    /// 生成時の母語（言語コード）。母語設定変更後の再生成判断に使う。
    var aiInfoLanguage: String?

    @Relationship(deleteRule: .cascade, inverse: \WordOccurrence.word)
    var occurrences: [WordOccurrence] = []

    init(
        id: UUID = UUID(),
        text: String,
        translation: String,
        exampleSentence: String? = nil,
        exampleSentenceSource: ExampleSentenceSource? = nil,
        partOfSpeech: String? = nil,
        grammarNote: String? = nil,
        registeredAt: Date = .now
    ) {
        self.id = id
        self.text = text
        self.translation = translation
        self.exampleSentence = exampleSentence
        self.exampleSentenceSource = exampleSentenceSource
        self.partOfSpeech = partOfSpeech
        self.grammarNote = grammarNote
        self.registeredAt = registeredAt
        self.reviewState = WordReviewState(dueDate: registeredAt)
    }
}

enum ExampleSentenceSource: String, Codable {
    case textbook
    case aiGenerated
}

enum WordAIInfoStatus: String, Codable {
    case none
    case generating
    case completed
    case failed
}

/// バックエンド /api/word-info のレスポンス wordInfo と同構造（backend/src/wordInfo.ts）。
/// フィールドを増減する場合は両方を合わせること。
struct WordAIInfo: Codable {
    struct Sense: Codable {
        /// 母語での意味
        var meaning: String
        /// 英語での定義・言い換え（英英辞書スタイル）
        var englishDefinition: String
        /// 品詞（母語表記。例:「動詞」）
        var partOfSpeech: String
        /// ニュアンス・使い分け
        var note: String?
    }

    struct Pronunciation: Codable {
        /// IPA発音記号（例: /ˈæp.əl/）
        var ipa: String
        /// 音節区切りとアクセント位置（例: AP-ple）
        var syllables: String?
    }

    struct Inflection: Codable {
        /// 変化の種類（母語。例:「過去形」）
        var form: String
        /// 変化形（例: "ran"）
        var text: String
    }

    struct Example: Codable {
        var english: String
        /// 母語訳
        var translation: String
    }

    /// 語義1〜3件。教科書文脈で使われた語義が先頭
    var senses: [Sense]
    var pronunciation: Pronunciation
    /// 語形変化（該当するもののみ。0件可）
    var inflections: [Inflection]
    /// 例文2〜3件
    var examples: [Example]
    /// よく使う組み合わせ（例: "make a decision"）
    var collocations: [String]
    var synonyms: [String]
    var antonyms: [String]
    /// 使用上の注意（可算/不可算、自他、前置詞の組み合わせ等）
    var usageNote: String?
    /// 難易度目安 "A1"〜"C2"
    var cefrLevel: String?
    /// 語源・記憶のヒント
    var etymology: String?
    /// 使用域（フォーマル/カジュアル/スラング等）
    var register: String?
    /// よくある間違い
    var commonMistakes: String?
}

struct WordReviewState: Codable {
    var dueDate: Date
    var lastReviewedAt: Date?
    var reviewCount: Int

    init(dueDate: Date, lastReviewedAt: Date? = nil, reviewCount: Int = 0) {
        self.dueDate = dueDate
        self.lastReviewedAt = lastReviewedAt
        self.reviewCount = reviewCount
    }
}
