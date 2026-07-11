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

    /// 位置情報（オフセット・ブロック番号）付きリンクの往復（本文タップの文脈切り出しに使う）
    @Test func urlRoundTripWithOffsets() throws {
        let url = try #require(EnglishWordLink.linkURL(for: "up", offset: 12, blockIndex: 3))
        let tap = try #require(EnglishWordLink.tapPayload(from: url))
        #expect(tap.word == "up")
        #expect(tap.offset == 12)
        #expect(tap.blockIndex == 3)
    }

    /// 位置情報なしの従来リンクは offset / blockIndex が nil のままデコードできる
    @Test func tapPayloadWithoutOffsetsIsNil() throws {
        let url = try #require(EnglishWordLink.linkURL(for: "apple"))
        let tap = try #require(EnglishWordLink.tapPayload(from: url))
        #expect(tap.word == "apple")
        #expect(tap.offset == nil)
        #expect(tap.blockIndex == nil)
    }

    // MARK: - 文脈（タップ語を含む文）の切り出し

    /// テキスト内で substring が最初に現れる文字オフセット（リンク URL の `o` と同じ数え方）
    private func charOffset(of substring: String, in text: String) throws -> Int {
        let range = try #require(text.range(of: substring))
        return text.distance(from: text.startIndex, to: range.lowerBound)
    }

    @Test func sentenceContextExtractsMiddleSentence() throws {
        let text = "He runs fast. I looked it up yesterday. She smiled."
        let offset = try charOffset(of: "up yesterday", in: text)
        let context = EnglishWordLink.sentenceContext(in: text, around: offset, wordLength: 2)
        #expect(context == "I looked it up yesterday.")
    }

    @Test func sentenceContextHandlesTextEdges() {
        // 文頭の語（前に境界なし）と文末の語（後ろに境界なし・終端記号なし）
        let text = "Take care of your brother"
        let head = EnglishWordLink.sentenceContext(in: text, around: 0, wordLength: 4)
        #expect(head == "Take care of your brother")
        let tail = EnglishWordLink.sentenceContext(in: text, around: 18, wordLength: 7)
        #expect(tail == "Take care of your brother")
    }

    @Test func sentenceContextStopsAtNewline() throws {
        let text = "First line words\nSecond line target here\nThird line"
        let offset = try charOffset(of: "target", in: text)
        let context = EnglishWordLink.sentenceContext(in: text, around: offset, wordLength: 6)
        #expect(context == "Second line target here")
    }

    /// 「3.5」のような語中ピリオド（直後が空白でない）は文境界にしない
    @Test func sentenceContextIgnoresMidTokenPeriod() throws {
        let text = "Version 3.5 looks it up quickly."
        let offset = try charOffset(of: "up quickly", in: text)
        let context = EnglishWordLink.sentenceContext(in: text, around: offset, wordLength: 2)
        #expect(context == "Version 3.5 looks it up quickly.")
    }

    /// 上限を超える長文はタップ語を中心にしたウィンドウへ丸める（タップ語を必ず含む）
    @Test func sentenceContextClampsLongSentenceAroundWord() throws {
        let text = String(repeating: "aaaa ", count: 40) + "look it up " + String(repeating: "bbbb ", count: 40)
        let offset = try charOffset(of: "up ", in: text)
        let context = try #require(
            EnglishWordLink.sentenceContext(in: text, around: offset, wordLength: 2, maxLength: 60)
        )
        #expect(context.count <= 60)
        #expect(context.contains("up"))
        #expect(context.contains("look it"))
    }

    @Test func sentenceContextReturnsNilForEmptyText() {
        #expect(EnglishWordLink.sentenceContext(in: "", around: 0, wordLength: 1) == nil)
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
