import XCTest
@testable import ESLLearningAssistant

final class WordIllustrationStoreTests: XCTestCase {
    private let word = "WordIllustrationStoreTests-sample"
    private let data = Data("dummy png bytes".utf8)

    override func tearDown() {
        WordIllustrationStore.removeAll()
        super.tearDown()
    }

    func testSaveThenLocalURLReturnsFile() throws {
        XCTAssertNil(WordIllustrationStore.localURL(word: word, targetLanguage: "ja"))

        let saved = try WordIllustrationStore.save(data: data, word: word, targetLanguage: "ja")
        let found = WordIllustrationStore.localURL(word: word, targetLanguage: "ja")
        XCTAssertEqual(found, saved)
        XCTAssertEqual(try Data(contentsOf: saved), data)
    }

    func testDifferentLanguageOrSenseIndexUsesDifferentKey() throws {
        try WordIllustrationStore.save(data: data, word: word, targetLanguage: "ja")

        // targetLanguage / senseIndex が違えば別キー＝未生成扱いになる
        XCTAssertNil(WordIllustrationStore.localURL(word: word, targetLanguage: "ko"))
        XCTAssertNil(WordIllustrationStore.localURL(word: word, targetLanguage: "ja", senseIndex: 1))

        let key1 = WordIllustrationStore.key(word: word, targetLanguage: "ja")
        let key2 = WordIllustrationStore.key(word: word, targetLanguage: "ko")
        let key3 = WordIllustrationStore.key(word: word, targetLanguage: "ja", senseIndex: 1)
        XCTAssertNotEqual(key1, key2)
        XCTAssertNotEqual(key1, key3)
        // サーバ側（sha256("model|word|target_language|sense_index")）と同じ形式の64桁hex
        XCTAssertEqual(key1.count, 64)
    }

    func testKeyNormalizesWordLikeServer() {
        // サーバ側 normalizeWordKey（trim + 小文字化）と同じ正規化でキーが一致すること
        let key1 = WordIllustrationStore.key(word: " Apple ", targetLanguage: "ja")
        let key2 = WordIllustrationStore.key(word: "apple", targetLanguage: "ja")
        XCTAssertEqual(key1, key2)
    }

    func testRemoveAllClearsSavedFiles() throws {
        try WordIllustrationStore.save(data: data, word: word, targetLanguage: "ja")
        WordIllustrationStore.removeAll()
        XCTAssertNil(WordIllustrationStore.localURL(word: word, targetLanguage: "ja"))
    }
}
