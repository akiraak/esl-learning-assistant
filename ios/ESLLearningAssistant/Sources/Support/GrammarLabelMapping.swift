import Foundation

/// `Sense.partOfSpeech` / `Inflection.form` は母語（日本語）表記で保存されているため、
/// 全英語の問題文（TC7・TC8・TT3・VC7）に使う英語ラベルへ変換する固定マッピング。
/// マッピングに無いラベルの単語では該当形式を出題しない（FormatSelector 側でフォールバック）。
/// docs/plans/word-memorization-quiz.md §3.3。
enum GrammarLabelMapping {
    /// 品詞: 日本語 → 英語
    static let partOfSpeech: [String: String] = [
        "名詞": "noun",
        "動詞": "verb",
        "形容詞": "adjective",
        "副詞": "adverb",
        "代名詞": "pronoun",
        "前置詞": "preposition",
        "接続詞": "conjunction",
        "冠詞": "article",
        "限定詞": "determiner",
        "助動詞": "auxiliary verb",
        "間投詞": "interjection",
        "感動詞": "interjection",
        "句動詞": "phrasal verb",
        "熟語": "idiom",
        "イディオム": "idiom",
    ]

    /// TC8（品詞4択）の固定選択肢。写像先がこの4つ以外の単語では TC8 を出題しない
    static let posChoices: Set<String> = ["noun", "verb", "adjective", "adverb"]

    /// 活用形: 日本語 → 英語
    static let inflectionForm: [String: String] = [
        "過去形": "past tense",
        "過去分詞": "past participle",
        "現在分詞": "present participle",
        "進行形": "present participle",
        "動名詞": "gerund",
        "三人称単数現在": "third-person singular",
        "三単現": "third-person singular",
        "複数形": "plural",
        "比較級": "comparative",
        "最上級": "superlative",
        "現在形": "present tense",
        "原形": "base form",
    ]

    static func englishPartOfSpeech(for label: String) -> String? {
        partOfSpeech[normalize(label)]
    }

    static func englishInflectionForm(for label: String) -> String? {
        inflectionForm[normalize(label)]
    }

    private static func normalize(_ label: String) -> String {
        label.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
