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

    // 多義語の辞書式分割（docs/plans/dictionary-style-word-split.md）。
    // 同綴異義（fall=落ちる/秋 など）は別 Word エントリに分割し、この判別子で区別する。
    // 単語の同一性が実質 text から (text, senseGroupKey) に変わる。
    // 非オプショナル追加は SwiftData のライトウェイトマイグレーションを壊すため、必ず
    // optional + 既定 nil の nullable カラムにする（reviewState / WordReviewState のコメント参照）。
    // nil は主見出し（primary、単一見出しも含む）。兄弟見出し（別見出し）は "1","2"… の連番文字列。
    // イラストの senseIndex（primary=0, 兄弟=1,2…）にもこの番号を使う。
    var senseGroupKey: String?

    // AI生成情報（docs/plans/word-ai-info-generation.md）。
    // すべてoptional/デフォルトありにして既存データの軽量マイグレーションを維持する。
    var aiInfo: WordAIInfo?
    var aiInfoStatus: WordAIInfoStatus = WordAIInfoStatus.none
    /// AI生成が失敗したときのユーザー向けメッセージ（401時のAPI Secret案内など）
    var aiInfoErrorMessage: String?
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

extension Word {
    /// このエントリが担当する同綴異義グループ番号。nil（primary・単一見出し）は 0、兄弟は 1,2…。
    var senseGroupNumber: Int {
        senseGroupKey.flatMap { Int($0) } ?? 0
    }

    /// イラストのキャッシュキー要素。見出しごとに別画像を持たせるため senseGroupNumber をそのまま使う
    /// （primary=0, 兄弟=1,2…）。見出しごとに aiInfo が独立しているため絞り込みは不要。
    var illustrationSenseIndex: Int { senseGroupNumber }

    /// イラスト生成プロンプトに渡す、この見出しの英語定義（サーバは兄弟見出しの blob を持たないため直接渡す）
    var illustrationDefinition: String? { aiInfo?.senses.first?.englishDefinition }

    /// イラスト生成プロンプトに渡す、この見出しの例文
    var illustrationExampleSentence: String? { aiInfo?.examples.first?.english }
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

    /// 語源・意味が無関係な別見出し（同綴異義）のラベル。見出しごとに個別生成するためのヒント。
    struct Homograph: Codable {
        /// 別見出しの母語での意味（例:「秋」）
        var meaning: String
        /// 品詞（母語表記。例:「名詞」）
        var partOfSpeech: String
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

    /// この見出し語の語義1〜4件（関連多義のみ）。教科書文脈で使われた語義が先頭
    var senses: [Sense]
    /// 語源・意味が無関係な別見出し（同綴異義）。分割生成のトリガに使う。旧データには無いため optional
    var otherHomographs: [Homograph]?
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

/// 間隔反復の復習状態（docs/specs/data-model.md §5）。更新ロジックは ReviewScheduler。
struct WordReviewState: Codable {
    var dueDate: Date
    var lastReviewedAt: Date?
    var reviewCount: Int
    // stepIndex / correctCount / lapseCount は初期リリース後に追加したフィールド。
    // SwiftData は埋め込み Codable を個別カラムに展開するため、非オプショナルだと
    // 既存 Word 行を持つストアのライトウェイトマイグレーションが
    // 「mandatory destination attribute に値が無い」エラーで失敗しストアが開けなくなる。
    // ストレージをオプショナルにして nullable カラムとし、公開 API は computed で 0 を既定値にする。
    private var stepIndexStorage: Int?
    private var correctCountStorage: Int?
    private var lapseCountStorage: Int?
    private var masteryPercentStorage: Int?

    /// 現在の復習ステップ（ReviewScheduler.stepIntervalsInDays のインデックス）
    var stepIndex: Int {
        get { stepIndexStorage ?? 0 }
        set { stepIndexStorage = newValue }
    }
    /// 累計正解数
    var correctCount: Int {
        get { correctCountStorage ?? 0 }
        set { correctCountStorage = newValue }
    }
    /// 不正解でステップ0にリセットされた回数
    var lapseCount: Int {
        get { lapseCountStorage ?? 0 }
        set { lapseCountStorage = newValue }
    }
    /// 現在の周回の習熟度（0〜100%）。正解+25 / 不正解−25 で増減し、
    /// 100% でクリア（dueDate 前進）と同時に 0 へ戻る（ReviewScheduler.answered）
    var masteryPercent: Int {
        get { masteryPercentStorage ?? 0 }
        set { masteryPercentStorage = newValue }
    }

    // キー名は実プロパティ名と必ず一致させること。SwiftData は埋め込み Codable を
    // 実プロパティ名ベースで管理するため、CodingKeys でリネームすると読み書きのキーが
    // 一致せず、値が保存されない・常に既定値で読まれる（エラーにならず黙って壊れる）。
    enum CodingKeys: String, CodingKey {
        case dueDate
        case lastReviewedAt
        case reviewCount
        case stepIndexStorage
        case correctCountStorage
        case lapseCountStorage
        case masteryPercentStorage
    }

    init(
        dueDate: Date,
        lastReviewedAt: Date? = nil,
        reviewCount: Int = 0,
        stepIndex: Int = 0,
        correctCount: Int = 0,
        lapseCount: Int = 0,
        masteryPercent: Int = 0
    ) {
        self.dueDate = dueDate
        self.lastReviewedAt = lastReviewedAt
        self.reviewCount = reviewCount
        self.stepIndexStorage = stepIndex
        self.correctCountStorage = correctCount
        self.lapseCountStorage = lapseCount
        self.masteryPercentStorage = masteryPercent
    }

    // stepIndex / correctCount / lapseCount 追加前に保存されたデータを nil のまま読む（参照時に0扱い）
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dueDate = try container.decode(Date.self, forKey: .dueDate)
        lastReviewedAt = try container.decodeIfPresent(Date.self, forKey: .lastReviewedAt)
        reviewCount = try container.decodeIfPresent(Int.self, forKey: .reviewCount) ?? 0
        stepIndexStorage = try container.decodeIfPresent(Int.self, forKey: .stepIndexStorage)
        correctCountStorage = try container.decodeIfPresent(Int.self, forKey: .correctCountStorage)
        lapseCountStorage = try container.decodeIfPresent(Int.self, forKey: .lapseCountStorage)
        masteryPercentStorage = try container.decodeIfPresent(Int.self, forKey: .masteryPercentStorage)
    }
}
