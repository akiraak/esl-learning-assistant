import Foundation

/// 英文を「単語ごとにタップ可能」にするための純ロジック（UI非依存・テスト対象）。
///
/// 各単語へ独自スキーム `eslword://add?w=<word>` のリンクを張り、表示側は SwiftUI の
/// `openURL` を横取りしてタップを検出する。プレーン英文（`TappableEnglishText`）と
/// マークダウン英文（`TappableMarkdown`）の両方がこの型のトークナイザ・リンク組み立て・
/// URLデコードを共有する。
enum EnglishWordLink {
    /// 独自リンクのスキーム
    static let scheme = "eslword"

    // MARK: - トークナイズ

    /// 英文を「単語」と「区切り（空白・記号）」のトークン列へ分割する。
    /// アポストロフィ・ハイフンは単語内文字として扱う（don't, well-known）。
    static func tokenize(_ s: String) -> [(text: String, isWord: Bool)] {
        var tokens: [(text: String, isWord: Bool)] = []
        var current = ""
        var currentIsWord = false
        for c in s {
            let w = isWordChar(c)
            if current.isEmpty {
                current = String(c)
                currentIsWord = w
            } else if w == currentIsWord {
                current.append(c)
            } else {
                tokens.append((current, currentIsWord))
                current = String(c)
                currentIsWord = w
            }
        }
        if !current.isEmpty {
            tokens.append((current, currentIsWord))
        }
        return tokens
    }

    static func isWordChar(_ c: Character) -> Bool {
        c.isLetter || c == "'" || c == "\u{2019}" || c == "-"
    }

    /// ラテン文字（英語）1文字か。`Character.isLetter` は日本語（CJK）にも true を返すため、
    /// リンク対象を英単語に限定するにはこの判定を使う。基本ラテン + ラテン1補助/拡張（アクセント付き）を許容。
    static func isEnglishLetter(_ c: Character) -> Bool {
        guard c.unicodeScalars.count == 1, let s = c.unicodeScalars.first else { return false }
        let v = s.value
        let basicLatin = (v >= 0x41 && v <= 0x5A) || (v >= 0x61 && v <= 0x7A) // A-Z a-z
        let latinExtended = v >= 0x00C0 && v <= 0x024F && c.isLetter          // À-ɏ（アクセント付きラテン）
        return basicLatin || latinExtended
    }

    /// 単語トークンの「芯」。前後の非英字（アポストロフィ・ハイフン等）を除いた実語。
    /// 芯に英字が無い（"-" 単体・日本語のみ）か、非ラテン文字（CJK等）が混じる場合は nil を返し、
    /// リンク対象外とする（母語混在欄でも英単語だけをリンク化するため）。
    static func core(of token: String) -> String? {
        let core = token.trimmingCharacters(in: CharacterSet.letters.inverted)
        guard core.contains(where: isEnglishLetter) else { return nil }
        guard !core.contains(where: { $0.isLetter && !isEnglishLetter($0) }) else { return nil }
        return core
    }

    // MARK: - リンクURL

    /// 単語の芯から `eslword://add?w=<word>` を組み立てる。
    /// `'`・`-` を含む語も `URLComponents` 経由で安全にエンコードされる。
    static func linkURL(for core: String) -> URL? {
        var comps = URLComponents()
        comps.scheme = scheme
        comps.host = "add"
        comps.queryItems = [URLQueryItem(name: "w", value: core)]
        return comps.url
    }

    /// `eslword://` リンクから単語をデコードする（タップ検出時に使う）。
    static func word(from url: URL) -> String? {
        guard url.scheme == scheme,
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let w = comps.queryItems?.first(where: { $0.name == "w" })?.value,
              !w.isEmpty
        else { return nil }
        return w
    }

    // MARK: - マークダウンの単語リンク化

    /// マークダウン文字列の「単語だけ」を `[word](eslword://add?w=…)` に包む。
    /// 見出し `#`・強調 `*`/`_`・箇条書き `-` などの記法文字は非単語トークンとして素通しするため、
    /// 書式を壊さずに単語だけをリンク化できる（MarkdownUI で本文と同じ見た目に整える）。
    ///
    /// 破壊を避けるためのガード:
    /// - フェンスコードブロック（``` / ~~~）の中身はそのまま。
    /// - インラインコード（`` `...` ``）の中身はそのまま。
    /// - 生URL（http:// https:// www.）は分割してリンク化せず1つの塊として素通し。
    /// バックエンドのOCRは見出し・箇条書き・強調のみを出力する（リンク/コードは生成しない）ため、
    /// 通常はこれらのガードに触れない。
    static func linkedMarkdown(_ source: String) -> String {
        let lines = source.components(separatedBy: "\n")
        var result: [String] = []
        result.reserveCapacity(lines.count)
        var inFence = false
        for line in lines {
            if isFenceLine(line) {
                inFence.toggle()
                result.append(line)
            } else if inFence {
                result.append(line)
            } else {
                result.append(linkifyInline(line))
            }
        }
        return result.joined(separator: "\n")
    }

    /// 行がフェンスコードの開始/終了（```／~~~）か。先頭空白は許容する。
    private static func isFenceLine(_ line: String) -> Bool {
        let trimmed = line.drop(while: { $0 == " " })
        return trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~")
    }

    /// 1行分のインライン処理。インラインコード・生URLを避けつつ単語をリンク化する。
    static func linkifyInline(_ line: String) -> String {
        let chars = Array(line)
        var out = ""
        var word = ""
        var i = 0

        func flushWord() {
            guard !word.isEmpty else { return }
            if let core = core(of: word), let url = linkURL(for: core) {
                out += "[\(word)](\(url.absoluteString))"
            } else {
                out += word
            }
            word = ""
        }

        while i < chars.count {
            let c = chars[i]

            // インラインコード: 同じ長さのバッククォート列で囲まれた区間は中身を素通し
            if c == "`" {
                flushWord()
                var openCount = 0
                while i < chars.count, chars[i] == "`" { openCount += 1; i += 1 }
                out += String(repeating: "`", count: openCount)
                let contentStart = i
                var j = i
                var closeStart: Int?
                while j < chars.count {
                    if chars[j] == "`" {
                        let runStart = j
                        var m = 0
                        while j < chars.count, chars[j] == "`" { m += 1; j += 1 }
                        if m == openCount { closeStart = runStart; break }
                    } else {
                        j += 1
                    }
                }
                if let closeStart {
                    out += String(chars[contentStart..<closeStart])
                    out += String(repeating: "`", count: openCount)
                    i = closeStart + openCount
                } else {
                    // 閉じが無ければ以降はコードとみなして素通し（リンク化しない）
                    out += String(chars[contentStart...])
                    i = chars.count
                }
                continue
            }

            // 生URLは分割せず1つの塊として素通しする
            if let end = rawURLEnd(chars, from: i) {
                flushWord()
                out += String(chars[i..<end])
                i = end
                continue
            }

            if isWordChar(c) {
                word.append(c)
                i += 1
            } else {
                flushWord()
                out.append(c)
                i += 1
            }
        }
        flushWord()
        return out
    }

    /// i から生URL（http:// https:// www.）が始まる場合、その終端（空白直前まで）のインデックスを返す。
    private static func rawURLEnd(_ chars: [Character], from i: Int) -> Int? {
        let prefixes = ["https://", "http://", "www."]
        for prefix in prefixes {
            let p = Array(prefix)
            guard i + p.count <= chars.count else { continue }
            var matched = true
            for k in 0..<p.count where Character(chars[i + k].lowercased()) != p[k] {
                matched = false
                break
            }
            guard matched else { continue }
            var end = i + p.count
            while end < chars.count, !chars[end].isWhitespace { end += 1 }
            return end
        }
        return nil
    }
}
