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

    // 単一段落（インライン強調のみ）はブロック分割の影響を受けない
    // ＝TTSキャッシュキー sha256("model|text") が変わらないことの回帰テスト
    func testSingleParagraphKeepsInlineOnlyOutput() {
        XCTAssertEqual(
            MarkdownPlainText.plainText("The **north wind** and the sun argued about strength."),
            "The north wind and the sun argued about strength."
        )
        // 段落内の単一改行（ソフト改行）はスペースになる（Markdown 仕様どおり、ブロック分割はされない）
        XCTAssertEqual(
            MarkdownPlainText.plainText("line one\nline two"),
            "line one line two"
        )
        XCTAssertEqual(
            MarkdownPlainText.plainText("Plain sentence without any markup."),
            "Plain sentence without any markup."
        )
    }

    func testNilAndEmptyReturnEmpty() {
        XCTAssertEqual(MarkdownPlainText.plainText(nil), "")
        XCTAssertEqual(MarkdownPlainText.plainText(""), "")
    }
}
