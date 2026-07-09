import XCTest
@testable import ESLLearningAssistant

final class MarkdownPlainTextTests: XCTestCase {
    // 見出しと直後の段落が空行で区切られる（TTSが息継ぎなしで連結読みしないように）
    func testHeadingAndParagraphAreSeparated() {
        XCTAssertEqual(
            MarkdownPlainText.plainText("# The Sun and the Wind\n\nThe north wind and the sun argued."),
            "The Sun and the Wind\n\nThe north wind and the sun argued."
        )
    }

    func testListItemsAreSeparated() {
        XCTAssertEqual(
            MarkdownPlainText.plainText("- first item\n- second item"),
            "first item\n\nsecond item"
        )
    }

    func testInlineMarkupIsStrippedWithoutSplittingBlock() {
        XCTAssertEqual(
            MarkdownPlainText.plainText("This is **bold** and *italic* text."),
            "This is bold and italic text."
        )
    }

    // 単一段落（インライン強調のみ）は旧実装と出力が一致する
    // ＝TTSキャッシュキー sha256("model|text") が変わらないことの回帰テスト
    func testSingleParagraphMatchesLegacyOutput() {
        let cases = [
            "The **north wind** and the sun argued about strength.",
            "line one\nline two",
            "Plain sentence without any markup.",
        ]
        for markdown in cases {
            XCTAssertEqual(
                MarkdownPlainText.plainText(markdown),
                MarkdownPlainText.legacyPlainText(markdown),
                "単一ブロックのキャッシュキーが変わってしまう: \(markdown)"
            )
        }
    }

    // 旧実装がブロック境界を落とすこと自体の記録（リキー移行が前提にしている挙動）
    func testLegacyDropsBlockBoundaries() {
        XCTAssertEqual(
            MarkdownPlainText.legacyPlainText("# Title\n\nBody paragraph."),
            "TitleBody paragraph."
        )
    }

    func testNilAndEmptyReturnEmpty() {
        XCTAssertEqual(MarkdownPlainText.plainText(nil), "")
        XCTAssertEqual(MarkdownPlainText.plainText(""), "")
        XCTAssertEqual(MarkdownPlainText.legacyPlainText(nil), "")
        XCTAssertEqual(MarkdownPlainText.legacyPlainText(""), "")
    }
}
