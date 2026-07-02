import XCTest
@testable import ESLLearningAssistant

final class TTSAudioStoreTests: XCTestCase {
    private let text = "TTSAudioStoreTests sample sentence."
    private let data = Data("dummy wav bytes".utf8)

    override func tearDown() {
        TTSAudioStore.removeAll()
        super.tearDown()
    }

    func testSaveThenLocalURLReturnsFile() throws {
        XCTAssertNil(TTSAudioStore.localURL(text: text, voice: "chobi", model: "flash"))

        let saved = try TTSAudioStore.save(data: data, text: text, voice: "chobi", model: "flash")
        let found = TTSAudioStore.localURL(text: text, voice: "chobi", model: "flash")
        XCTAssertEqual(found, saved)
        XCTAssertEqual(try Data(contentsOf: saved), data)
    }

    func testDifferentVoiceOrModelUsesDifferentKey() throws {
        try TTSAudioStore.save(data: data, text: text, voice: "chobi", model: "flash")

        // voice / model が違えば別キー＝未生成扱いになる
        XCTAssertNil(TTSAudioStore.localURL(text: text, voice: "naruko", model: "flash"))
        XCTAssertNil(TTSAudioStore.localURL(text: text, voice: "chobi", model: "pro"))

        let key1 = TTSAudioStore.key(text: text, voice: "chobi", model: "flash")
        let key2 = TTSAudioStore.key(text: text, voice: "naruko", model: "flash")
        let key3 = TTSAudioStore.key(text: text, voice: "chobi", model: "pro")
        XCTAssertNotEqual(key1, key2)
        XCTAssertNotEqual(key1, key3)
        // サーバ側（sha256("voice|model|text")）と同じ形式の64桁hex
        XCTAssertEqual(key1.count, 64)
    }

    func testRemoveAllClearsSavedFiles() throws {
        try TTSAudioStore.save(data: data, text: text, voice: "chobi", model: "flash")
        TTSAudioStore.removeAll()
        XCTAssertNil(TTSAudioStore.localURL(text: text, voice: "chobi", model: "flash"))
    }
}
