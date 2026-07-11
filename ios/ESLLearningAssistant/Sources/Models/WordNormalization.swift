import Foundation

/// 入力語を辞書見出し語（lemma）へ正規化した結果。バックエンド POST /api/word-normalize の
/// レスポンス（backend/src/wordNormalize.ts の WordNormalization）と同構造。
/// フィールドを増減する場合は両方を合わせること。
///
/// SwiftData には永続化しない（登録・派生生成の前段でのみ使うトランジェント）。実際に登録する
/// `Word.text` には status に応じて確定した lemma / 入力語を渡す（確認UIは Phase 2/3）。
struct WordNormalization: Codable, Equatable {
    /// バックエンドが受け取った入力語（サーバ側でトリム済み）
    let input: String
    /// 登録すべき見出し語。inflected/misspelled では常に原形（基本形）。
    /// 綴りを直した結果が変化形になる場合（例:「writed」）も原形（「write」）まで戻す。
    /// 複数語フレーズも中心動詞を原形化した辞書見出し（例:「looked up」→「look up」）。
    /// phrase_part ではタップ語を含む表現全体の辞書基本形（例: 文中の「up」→「look up」）。
    /// canonical/proper_noun/phrase/unknown では入力語と同じ。
    let lemma: String
    let status: WordNormalizeStatus
    /// なぜその lemma に直したかを母語で説明する1文。確認UIを出さない status では空文字列。
    let reason: String

    /// 実際に登録に使う見出し語。空白をトリムし、万一 lemma が空なら入力語へフォールバックする。
    var effectiveLemma: String {
        let trimmed = lemma.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? input.trimmingCharacters(in: .whitespacesAndNewlines) : trimmed
    }

    /// 原形/正しい綴りへ直す確認UIをユーザーに見せるべきか。
    /// status が訂正提案（inflected/misspelled）で、かつ lemma が入力と実際に異なる場合のみ true。
    /// 大小・前後空白だけの違いは「直すものが無い」とみなして false（無意味な確認を避ける）。
    var requiresConfirmation: Bool {
        guard status.suggestsCorrection else { return false }
        let candidate = effectiveLemma
        let source = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return false }
        return candidate.caseInsensitiveCompare(source) != .orderedSame
    }
}

/// 入力語の分類。確認UIの出し分けを決める（docs/plans/word-input-normalization.md）。
enum WordNormalizeStatus: String, Codable {
    /// 既に辞書見出し語（原形・正しい綴り）。lemma は入力と同じ。確認UIを出さず即登録。
    case canonical
    /// 語形変化（過去形・過去分詞・三単現・複数形・比較級など）。フレーズの変化形
    /// （looked up 等）も含む。lemma は原形。確認UIを出す。
    case inflected
    /// 綴り間違い。フレーズ内の綴り間違いも含む。lemma は正しい綴り。確認UIを出す。
    case misspelled
    /// 固有名詞（人名・地名など）。訂正せず lemma は入力と同じ。
    case properNoun = "proper_noun"
    /// 空白を含む複数語の連語（句動詞・イディオム等）で、既に辞書見出しの基本形のもの。
    /// 訂正せず lemma は入力と同じ。変化形・綴り間違いのフレーズは inflected / misspelled になる。
    case phrase
    /// 文脈付き呼び出し（本文タップ登録）で、タップ語が文中の複数語表現（句動詞・イディオム）の
    /// 一部として使われているもの。lemma は表現全体の辞書基本形（例: 文中の「up」→「look up」）。
    /// 確認UI（主=表現全体 / 逃げ道=タップ語のまま）を出す。docs/plans/word-phrase-support.md Phase 4。
    case phrasePart = "phrase_part"
    /// 英単語として判定できない・英語でない・明らかな文。lemma は入力と同じ。
    case unknown

    /// 訂正（原形化・綴り訂正・熟語提案）を提案する status か。true の時だけ確認UIの候補になる。
    var suggestsCorrection: Bool {
        switch self {
        case .inflected, .misspelled, .phrasePart: true
        case .canonical, .properNoun, .phrase, .unknown: false
        }
    }

    /// 未知・将来追加された status 値は .unknown として安全側（訂正しない）に扱う。
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = WordNormalizeStatus(rawValue: raw) ?? .unknown
    }
}
