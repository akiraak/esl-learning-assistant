import Foundation

/// タップ可能 Markdown 描画（`TappableMarkdown`）用の軽量 Markdown パーサ。UI 非依存・テスト対象。
///
/// なぜ独自実装か: MarkdownUI は1段落をインラインノード毎に `result = result + Text(...)` で連結するため
/// （`TextInlineRenderer.defaultRender`）、全単語をリンク化した長い段落では `ConcatenatedTextStorage`
/// （＝`Text + Text`）が数百〜千段ネストし、SwiftUI の `Text.resolve` の再帰が実機の ~1MB メインスレッド
/// スタックを溢れさせて `EXC_BAD_ACCESS`（Thread stack size exceeded）でクラッシュする。シミュレータは
/// スタックが ~8MB あるため無再現（[[markdownui-perword-link-stack-overflow]]）。
///
/// 対策として Markdown を**ブロック**（見出し / 箇条書き / 段落）へ分解し、各ブロックのインラインを
/// **強調スパン列**（太字 / 斜体）へ分解する。描画側は各ブロックを **1つの `Text(AttributedString)`** に
/// する（連結ゼロ＝再帰なし）ので、段落の語数に依らずクラッシュしない。
/// バックエンドの OCR / 文字起こしは「見出し `#`・箇条書き `-`・強調 `**`/`*`」のみ出力する想定。
enum MarkdownLite {
    /// インラインの強調スタイル。
    enum InlineStyle: Equatable {
        case normal
        case bold
        case italic
        case boldItalic
    }

    /// 強調スタイル付きのインライン断片。
    struct Span: Equatable {
        let text: String
        let style: InlineStyle
    }

    /// Markdown のブロック。
    enum Block: Equatable {
        case heading(level: Int, spans: [Span])
        case bullet(spans: [Span])
        case paragraph(spans: [Span])
    }

    // MARK: - ブロック分解

    /// Markdown をブロック列へ分解する。見出し(`#`〜`###`)・箇条書き(`- `/`* `)・段落（空行区切り、
    /// 連続する通常行は空白で連結）を扱う。
    static func blocks(_ markdown: String) -> [Block] {
        var blocks: [Block] = []
        var paragraphLines: [String] = []

        func flushParagraph() {
            guard !paragraphLines.isEmpty else { return }
            blocks.append(.paragraph(spans: inlineSpans(paragraphLines.joined(separator: " "))))
            paragraphLines.removeAll()
        }

        for rawLine in markdown.components(separatedBy: "\n") {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                flushParagraph()
            } else if let heading = headingMatch(trimmed) {
                flushParagraph()
                blocks.append(.heading(level: heading.level, spans: inlineSpans(heading.text)))
            } else if let item = bulletMatch(trimmed) {
                flushParagraph()
                blocks.append(.bullet(spans: inlineSpans(item)))
            } else {
                paragraphLines.append(trimmed)
            }
        }
        flushParagraph()
        return blocks
    }

    /// 行頭の `#`〜`###`（直後に空白）を見出しとして解釈する。レベルは 1〜3 に丸める。
    private static func headingMatch(_ line: String) -> (level: Int, text: String)? {
        var level = 0
        var idx = line.startIndex
        while idx < line.endIndex, line[idx] == "#", level < 6 {
            level += 1
            idx = line.index(after: idx)
        }
        guard level >= 1, idx < line.endIndex, line[idx] == " " else { return nil }
        let text = String(line[line.index(after: idx)...]).trimmingCharacters(in: .whitespaces)
        return (min(level, 3), text)
    }

    /// 行頭の `- ` / `* `（マーカー直後に空白）を箇条書きとして解釈する。
    /// 強調 `*word*` と誤認しないよう、マーカー直後の空白を必須にしている。
    private static func bulletMatch(_ line: String) -> String? {
        guard let first = line.first, first == "-" || first == "*" else { return nil }
        let after = line.index(after: line.startIndex)
        guard after < line.endIndex, line[after] == " " else { return nil }
        return String(line[line.index(after: after)...]).trimmingCharacters(in: .whitespaces)
    }

    // MARK: - インライン強調分解

    /// インライン Markdown の強調（`**bold**`/`__bold__`/`*italic*`/`_italic_`）をスタイル付きスパン列へ
    /// 分解する。マーカーは取り除く。閉じられないマーカーは素の文字として扱う（不正入力でも壊れない）。
    /// 入れ子は解釈しない（OCR 出力は入れ子強調を出さない）。
    static func inlineSpans(_ source: String) -> [Span] {
        let chars = Array(source)
        var spans: [Span] = []
        var buffer = ""
        var i = 0

        func flushNormal() {
            guard !buffer.isEmpty else { return }
            spans.append(Span(text: buffer, style: .normal))
            buffer = ""
        }

        while i < chars.count {
            let c = chars[i]
            if c == "*" || c == "_" {
                let isDouble = (i + 1 < chars.count && chars[i + 1] == c)
                let markerLength = isDouble ? 2 : 1
                let contentStart = i + markerLength
                if let close = findClosingMarker(chars, char: c, length: markerLength, from: contentStart),
                   close > contentStart {
                    flushNormal()
                    spans.append(
                        Span(text: String(chars[contentStart..<close]), style: isDouble ? .bold : .italic)
                    )
                    i = close + markerLength
                    continue
                }
            }
            buffer.append(c)
            i += 1
        }
        flushNormal()
        return spans.filter { !$0.text.isEmpty }
    }

    /// `char` を `length` 個並べたマーカー（`*`/`**`/`_`/`__`）の閉じ位置（開始インデックス）を from 以降で探す。
    private static func findClosingMarker(_ chars: [Character], char: Character, length: Int, from: Int) -> Int? {
        var i = from
        while i + length <= chars.count {
            var matched = true
            for k in 0..<length where chars[i + k] != char {
                matched = false
                break
            }
            // 2連マーカーを探すときは、ちょうど length 個で閉じる位置を採用する
            if matched {
                return i
            }
            i += 1
        }
        return nil
    }
}
