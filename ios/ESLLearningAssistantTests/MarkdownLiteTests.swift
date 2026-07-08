import Foundation
import Testing
@testable import ESLLearningAssistant

/// `MarkdownLite` のブロック分解・インライン強調分解を検証する。
/// （描画側 `TappableMarkdown` はこれを1ブロック=1つの `Text(AttributedString)` にして
/// `Text` 連結の再帰スタックオーバーフローを避ける。[[markdownui-perword-link-stack-overflow]]）
struct MarkdownLiteTests {
    // MARK: - blocks

    @Test func headingLevelsAreParsed() {
        #expect(MarkdownLite.blocks("# One") == [.heading(level: 1, spans: [.init(text: "One", style: .normal)])])
        #expect(MarkdownLite.blocks("## Two") == [.heading(level: 2, spans: [.init(text: "Two", style: .normal)])])
        #expect(MarkdownLite.blocks("### Three") == [.heading(level: 3, spans: [.init(text: "Three", style: .normal)])])
        // 4個以上は 3 に丸める
        #expect(MarkdownLite.blocks("#### Four") == [.heading(level: 3, spans: [.init(text: "Four", style: .normal)])])
    }

    @Test func hashWithoutSpaceIsNotHeading() {
        // "#tag" は見出しではなく段落
        #expect(MarkdownLite.blocks("#tag") == [.paragraph(spans: [.init(text: "#tag", style: .normal)])])
    }

    @Test func bulletsAreParsed() {
        #expect(MarkdownLite.blocks("- item") == [.bullet(spans: [.init(text: "item", style: .normal)])])
        #expect(MarkdownLite.blocks("* item") == [.bullet(spans: [.init(text: "item", style: .normal)])])
    }

    @Test func emphasisAtLineStartIsNotBullet() {
        // "*word*" は箇条書きではなく段落（斜体）— マーカー直後に空白が無いため
        #expect(MarkdownLite.blocks("*word*") == [.paragraph(spans: [.init(text: "word", style: .italic)])])
    }

    @Test func consecutiveLinesJoinIntoOneParagraph() {
        #expect(
            MarkdownLite.blocks("hello\nworld")
                == [.paragraph(spans: [.init(text: "hello world", style: .normal)])]
        )
    }

    @Test func blankLineSeparatesParagraphs() {
        #expect(
            MarkdownLite.blocks("a\n\nb")
                == [
                    .paragraph(spans: [.init(text: "a", style: .normal)]),
                    .paragraph(spans: [.init(text: "b", style: .normal)]),
                ]
        )
    }

    @Test func mixedDocumentStructure() {
        let md = "# Title\n\nFirst line\nsecond line\n\n- one\n- two"
        #expect(
            MarkdownLite.blocks(md)
                == [
                    .heading(level: 1, spans: [.init(text: "Title", style: .normal)]),
                    .paragraph(spans: [.init(text: "First line second line", style: .normal)]),
                    .bullet(spans: [.init(text: "one", style: .normal)]),
                    .bullet(spans: [.init(text: "two", style: .normal)]),
                ]
        )
    }

    // MARK: - inline emphasis

    @Test func boldIsParsed() {
        #expect(MarkdownLite.inlineSpans("**hi**") == [.init(text: "hi", style: .bold)])
        #expect(MarkdownLite.inlineSpans("__hi__") == [.init(text: "hi", style: .bold)])
    }

    @Test func italicIsParsed() {
        #expect(MarkdownLite.inlineSpans("*hi*") == [.init(text: "hi", style: .italic)])
        #expect(MarkdownLite.inlineSpans("_hi_") == [.init(text: "hi", style: .italic)])
    }

    @Test func emphasisWithinText() {
        #expect(
            MarkdownLite.inlineSpans("a **b** c")
                == [
                    .init(text: "a ", style: .normal),
                    .init(text: "b", style: .bold),
                    .init(text: " c", style: .normal),
                ]
        )
    }

    @Test func unclosedMarkerIsLiteral() {
        // 閉じられない ** は素の文字として残す（不正入力で壊れない）
        #expect(MarkdownLite.inlineSpans("a ** b") == [.init(text: "a ** b", style: .normal)])
    }

    @Test func plainTextHasSingleNormalSpan() {
        #expect(MarkdownLite.inlineSpans("just words") == [.init(text: "just words", style: .normal)])
    }

    // MARK: - 長い段落でもブロック数は段落数（＝1）で、Text 連結の再帰源にならない

    @Test func longParagraphStaysSingleBlock() {
        let para = Array(repeating: "word", count: 600).joined(separator: " ")
        let blocks = MarkdownLite.blocks(para)
        #expect(blocks.count == 1)
        if case .paragraph(let spans) = blocks[0] {
            #expect(spans == [.init(text: para, style: .normal)])
        } else {
            Issue.record("expected a single paragraph block")
        }
    }
}
