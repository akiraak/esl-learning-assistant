import Foundation
import Testing
@testable import ESLLearningAssistant

/// `EnglishWordLink` のトークナイズ・マークダウン単語リンク化・URL往復を検証する。
struct EnglishWordLinkTests {
    // MARK: - トークナイズ

    @Test func tokenizeSplitsWordsAndSeparators() {
        let tokens = EnglishWordLink.tokenize("Hello, world!")
        #expect(tokens.map(\.text) == ["Hello", ", ", "world", "!"])
        #expect(tokens.map(\.isWord) == [true, false, true, false])
    }

    @Test func apostropheAndHyphenAreWordChars() {
        #expect(EnglishWordLink.tokenize("don't").map(\.text) == ["don't"])
        #expect(EnglishWordLink.tokenize("well-known").map(\.text) == ["well-known"])
    }

    // MARK: - core（リンク対象判定）

    @Test func coreRejectsNonLetterTokens() {
        #expect(EnglishWordLink.core(of: "-") == nil)
        #expect(EnglishWordLink.core(of: "--") == nil)
        #expect(EnglishWordLink.core(of: "'") == nil)
    }

    @Test func coreTrimsEdgePunctuation() {
        #expect(EnglishWordLink.core(of: "'tis") == "tis")
        #expect(EnglishWordLink.core(of: "well-known") == "well-known")
    }

    @Test func coreRejectsJapaneseAndMixedTokens() {
        // 日本語のみ・ラテン混在は英単語ではないのでリンク対象外
        #expect(EnglishWordLink.core(of: "りんご") == nil)
        #expect(EnglishWordLink.core(of: "試験") == nil)
        #expect(EnglishWordLink.core(of: "TOEIC試験") == nil)
    }

    @Test func coreAcceptsAccentedLatin() {
        // 合成済み é（U+00E9）で判定を確定させる
        let cafe = "caf\u{00E9}"
        #expect(EnglishWordLink.core(of: cafe) == cafe)
    }

    // MARK: - URL 往復

    @Test func urlRoundTrip() throws {
        let url = try #require(EnglishWordLink.linkURL(for: "don't"))
        #expect(url.scheme == "eslword")
        #expect(EnglishWordLink.word(from: url) == "don't")
    }

    @Test func wordFromRejectsForeignScheme() throws {
        let https = try #require(URL(string: "https://example.com?w=apple"))
        #expect(EnglishWordLink.word(from: https) == nil)
    }

    // MARK: - マークダウン単語リンク化

    @Test func linkedMarkdownWrapsWordsAsLinks() {
        let out = EnglishWordLink.linkedMarkdown("The cat")
        #expect(out == "[The](eslword://add?w=The) [cat](eslword://add?w=cat)")
    }

    @Test func linkedMarkdownPreservesHeadingMarker() {
        let out = EnglishWordLink.linkedMarkdown("# Chapter")
        #expect(out == "# [Chapter](eslword://add?w=Chapter)")
    }

    @Test func linkedMarkdownPreservesBoldAndBullets() {
        // 強調はリンクを内包する有効なマークダウンになる／箇条書きマーカーは素通し
        #expect(EnglishWordLink.linkedMarkdown("**hi**") == "**[hi](eslword://add?w=hi)**")
        #expect(EnglishWordLink.linkedMarkdown("- item") == "- [item](eslword://add?w=item)")
    }

    @Test func linkedMarkdownLeavesJapaneseUntouched() {
        // 日本語混在でも英単語だけをリンク化する
        let out = EnglishWordLink.linkedMarkdown("これは apple です")
        #expect(out == "これは [apple](eslword://add?w=apple) です")
    }

    @Test func linkedMarkdownSkipsFencedCode() {
        let src = "```\nlet x = go()\n```"
        // フェンス内はそのまま（go がリンク化されない）
        #expect(EnglishWordLink.linkedMarkdown(src) == src)
    }

    @Test func linkedMarkdownSkipsInlineCode() {
        // コード外の単語はリンク化し、インラインコードの中身 `map` だけ素通しする
        let out = EnglishWordLink.linkedMarkdown("use `map` here")
        #expect(out == "[use](eslword://add?w=use) `map` [here](eslword://add?w=here)")
    }

    @Test func linkedMarkdownSkipsRawURL() {
        // URL前後の単語はリンク化し、生URLは分割せず1塊のまま素通しする
        let out = EnglishWordLink.linkedMarkdown("see https://a.com/x now")
        #expect(out == "[see](eslword://add?w=see) https://a.com/x [now](eslword://add?w=now)")
    }

    @Test func linkedMarkdownPreservesLineStructure() {
        let out = EnglishWordLink.linkedMarkdown("a\n\nb")
        #expect(out == "[a](eslword://add?w=a)\n\n[b](eslword://add?w=b)")
    }
}
