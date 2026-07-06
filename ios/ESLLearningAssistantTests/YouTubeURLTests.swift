import Foundation
import Testing
@testable import ESLLearningAssistant

/// `YouTubeURL` の videoID 抽出を検証する。動画ID直接・各種 URL 形式・不正入力を網羅する。
struct YouTubeURLTests {
    // MARK: - 動画ID直接

    @Test func bareValidIDReturnsItself() {
        #expect(YouTubeURL.videoID(from: "dQw4w9WgXcQ") == "dQw4w9WgXcQ")
        // `_` と `-` を含むID
        #expect(YouTubeURL.videoID(from: "aBc-dE_1234") == "aBc-dE_1234")
    }

    @Test func surroundingWhitespaceIsTrimmed() {
        #expect(YouTubeURL.videoID(from: "  dQw4w9WgXcQ \n") == "dQw4w9WgXcQ")
    }

    // MARK: - URL 形式

    @Test func watchURLReturnsID() {
        #expect(YouTubeURL.videoID(from: "https://www.youtube.com/watch?v=dQw4w9WgXcQ") == "dQw4w9WgXcQ")
    }

    @Test func watchURLWithExtraParamsReturnsID() {
        #expect(YouTubeURL.videoID(from: "https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=30s&feature=share") == "dQw4w9WgXcQ")
    }

    @Test func shortYoutuBeReturnsID() {
        #expect(YouTubeURL.videoID(from: "https://youtu.be/dQw4w9WgXcQ") == "dQw4w9WgXcQ")
        // タイムスタンプ付き
        #expect(YouTubeURL.videoID(from: "https://youtu.be/dQw4w9WgXcQ?t=42") == "dQw4w9WgXcQ")
    }

    @Test func shortsEmbedLiveReturnID() {
        #expect(YouTubeURL.videoID(from: "https://www.youtube.com/shorts/dQw4w9WgXcQ") == "dQw4w9WgXcQ")
        #expect(YouTubeURL.videoID(from: "https://www.youtube.com/embed/dQw4w9WgXcQ") == "dQw4w9WgXcQ")
        #expect(YouTubeURL.videoID(from: "https://www.youtube.com/live/dQw4w9WgXcQ") == "dQw4w9WgXcQ")
    }

    @Test func schemelessURLReturnsID() {
        #expect(YouTubeURL.videoID(from: "www.youtube.com/watch?v=dQw4w9WgXcQ") == "dQw4w9WgXcQ")
        #expect(YouTubeURL.videoID(from: "youtu.be/dQw4w9WgXcQ") == "dQw4w9WgXcQ")
    }

    @Test func mobileAndMusicHostsReturnID() {
        #expect(YouTubeURL.videoID(from: "https://m.youtube.com/watch?v=dQw4w9WgXcQ") == "dQw4w9WgXcQ")
        #expect(YouTubeURL.videoID(from: "https://music.youtube.com/watch?v=dQw4w9WgXcQ") == "dQw4w9WgXcQ")
    }

    // MARK: - 不正入力

    @Test func invalidInputsReturnNil() {
        #expect(YouTubeURL.videoID(from: "") == nil)
        #expect(YouTubeURL.videoID(from: "   ") == nil)
        // 10桁・12桁（長さ違い）
        #expect(YouTubeURL.videoID(from: "dQw4w9WgXc") == nil)
        #expect(YouTubeURL.videoID(from: "dQw4w9WgXcQQ") == nil)
        // 不正文字を含む11文字
        #expect(YouTubeURL.videoID(from: "dQw4w9WgXc!") == nil)
        // YouTube ではない URL
        #expect(YouTubeURL.videoID(from: "https://example.com/watch?v=dQw4w9WgXcQ") == nil)
        // v パラメータが不正長
        #expect(YouTubeURL.videoID(from: "https://www.youtube.com/watch?v=short") == nil)
    }

    // MARK: - isValidID

    @Test func isValidIDChecksLengthAndCharset() {
        #expect(YouTubeURL.isValidID("dQw4w9WgXcQ"))
        #expect(!YouTubeURL.isValidID("dQw4w9WgXc"))   // 10桁
        #expect(!YouTubeURL.isValidID("dQw4 9WgXcQ"))  // 空白
    }
}
