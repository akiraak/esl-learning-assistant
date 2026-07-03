import Foundation

// MARK: - 問題データ

/// 復習クイズ1問。サーバ（/api/quiz-questions、backend/src/quizQuestions.ts）で
/// AI 生成・保存された question_json と 1:1 対応する。
/// 音声・イラストのファイル解決や再生は View 側で行う。
struct ReviewQuestion: Codable {
    var format: ReviewQuestionFormat
    /// 画面上部に表示する英語の指示文
    var instruction: String
    /// 表示する本文（英語定義・空所つき例文など）。音声のみの出題では nil
    var displayText: String?
    /// 再生する音声のテキスト（音声出題形式のみ。TTS / 内蔵読み上げの対象）
    var audioText: String?
    /// 出題として表示するイラストの単語（IC1・IT1）
    var promptIllustrationWord: String?
    var answer: ReviewQuestionAnswer
}

enum ReviewQuestionAnswer {
    /// テキスト4択
    case choices(options: [String], correctIndex: Int)
    /// イラスト4択（要素は各単語のテキスト。イラストの解決は View 側）
    case illustrationChoices(options: [String], correctIndex: Int)
    /// テキスト入力
    case typing(ReviewTypingSpec)
}

/// テキスト入力回答の判定仕様（判定は ReviewAnswerJudge）
struct ReviewTypingSpec {
    /// 正規化後にこのいずれかと一致すれば正解
    var acceptedAnswers: [String]
    /// VT2（例文ディクテーション）の単語一致率しきい値。nil なら完全一致
    var matchRateThreshold: Double?

    init(acceptedAnswers: [String], matchRateThreshold: Double? = nil) {
        self.acceptedAnswers = acceptedAnswers
        self.matchRateThreshold = matchRateThreshold
    }
}

// サーバ JSON の answer は {type, options, correctIndex, acceptedAnswers, matchRateThreshold} の
// フラット形式。type で判別し、範囲・空配列などの壊れたデータはデコード段階で弾く
// （呼び出し側は decode 失敗した問題を出題対象から外す）。
extension ReviewQuestionAnswer: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case options
        case correctIndex
        case acceptedAnswers
        case matchRateThreshold
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "choices", "illustrationChoices":
            let options = try container.decode([String].self, forKey: .options)
            let correctIndex = try container.decode(Int.self, forKey: .correctIndex)
            guard !options.isEmpty, options.indices.contains(correctIndex) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .correctIndex, in: container,
                    debugDescription: "correctIndex out of range"
                )
            }
            self = type == "choices"
                ? .choices(options: options, correctIndex: correctIndex)
                : .illustrationChoices(options: options, correctIndex: correctIndex)
        case "typing":
            let accepted = try container.decode([String].self, forKey: .acceptedAnswers)
            guard !accepted.isEmpty else {
                throw DecodingError.dataCorruptedError(
                    forKey: .acceptedAnswers, in: container,
                    debugDescription: "acceptedAnswers is empty"
                )
            }
            let threshold = try container.decodeIfPresent(Double.self, forKey: .matchRateThreshold)
            self = .typing(ReviewTypingSpec(acceptedAnswers: accepted, matchRateThreshold: threshold))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: container,
                debugDescription: "unknown answer type: \(type)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .choices(let options, let correctIndex):
            try container.encode("choices", forKey: .type)
            try container.encode(options, forKey: .options)
            try container.encode(correctIndex, forKey: .correctIndex)
        case .illustrationChoices(let options, let correctIndex):
            try container.encode("illustrationChoices", forKey: .type)
            try container.encode(options, forKey: .options)
            try container.encode(correctIndex, forKey: .correctIndex)
        case .typing(let spec):
            try container.encode("typing", forKey: .type)
            try container.encode(spec.acceptedAnswers, forKey: .acceptedAnswers)
            try container.encodeIfPresent(spec.matchRateThreshold, forKey: .matchRateThreshold)
        }
    }
}

// MARK: - テキスト入力回答の判定

/// テキスト入力（TT / IT / VTT / VT 系）の判定。
/// しきい値（matchRateThreshold）はサーバ生成時に付与される（VT2 のみ 0.8）。
enum ReviewAnswerJudge {
    /// 小文字化・前後空白除去・句読点除去（単語内のアポストロフィは保持）・空白の圧縮
    static func normalize(_ text: String) -> String {
        let lowered = text.lowercased().replacingOccurrences(of: "’", with: "'")
        let punctuation = CharacterSet.punctuationCharacters.subtracting(CharacterSet(charactersIn: "'"))
        let scalars = lowered.unicodeScalars.map { punctuation.contains($0) ? " " as UnicodeScalar : $0 }
        return String(String.UnicodeScalarView(scalars))
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    /// 入力が仕様の正解に一致するか。matchRateThreshold があれば単語一致率で判定する
    static func isCorrect(input: String, spec: ReviewTypingSpec) -> Bool {
        let normalizedInput = normalize(input)
        guard !normalizedInput.isEmpty else { return false }
        if let threshold = spec.matchRateThreshold {
            return spec.acceptedAnswers.contains {
                wordMatchRate(input: normalizedInput, reference: $0) >= threshold
            }
        }
        return spec.acceptedAnswers.contains { normalize($0) == normalizedInput }
    }

    /// 単語単位の一致率（LCS 長 / 単語数の多い方）。挿入・欠落・置換をまとめて減点する
    static func wordMatchRate(input: String, reference: String) -> Double {
        let a = normalize(input).split(separator: " ").map(String.init)
        let b = normalize(reference).split(separator: " ").map(String.init)
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        var previous = [Int](repeating: 0, count: b.count + 1)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            for j in 1...b.count {
                current[j] = a[i - 1] == b[j - 1]
                    ? previous[j - 1] + 1
                    : max(previous[j], current[j - 1])
            }
            swap(&previous, &current)
            current = [Int](repeating: 0, count: b.count + 1)
        }
        return Double(previous[b.count]) / Double(max(a.count, b.count))
    }
}
