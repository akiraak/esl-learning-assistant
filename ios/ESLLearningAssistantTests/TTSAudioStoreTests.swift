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
        XCTAssertNil(TTSAudioStore.localURL(text: text, model: "flash"))

        let saved = try TTSAudioStore.save(data: data, text: text, model: "flash")
        let found = TTSAudioStore.localURL(text: text, model: "flash")
        XCTAssertEqual(found, saved)
        XCTAssertEqual(try Data(contentsOf: saved), data)
    }

    func testDifferentModelOrTextUsesDifferentKey() throws {
        try TTSAudioStore.save(data: data, text: text, model: "flash")

        // model / text が違えば別キー＝未生成扱いになる
        XCTAssertNil(TTSAudioStore.localURL(text: text, model: "pro"))
        XCTAssertNil(TTSAudioStore.localURL(text: text + " extra", model: "flash"))

        let key1 = TTSAudioStore.key(text: text, model: "flash")
        let key2 = TTSAudioStore.key(text: text, model: "pro")
        let key3 = TTSAudioStore.key(text: text + " extra", model: "flash")
        XCTAssertNotEqual(key1, key2)
        XCTAssertNotEqual(key1, key3)
        // サーバ側（sha256("model|text")）と同じ形式の64桁hex
        XCTAssertEqual(key1.count, 64)
    }

    func testRemoveAllClearsSavedFiles() throws {
        try TTSAudioStore.save(data: data, text: text, model: "flash")
        TTSAudioStore.removeAll()
        XCTAssertNil(TTSAudioStore.localURL(text: text, model: "flash"))
    }

    // MARK: - rekeyLocalFile（TTSCacheRekeyMigration 用のキー付け替え）

    func testRekeyLocalFileMovesToNewKey() throws {
        let newText = text + "\n\nrekeyed"
        try TTSAudioStore.save(data: data, text: text, model: "flash")

        TTSAudioStore.rekeyLocalFile(oldText: text, newText: newText, model: "flash")

        XCTAssertNil(TTSAudioStore.localURL(text: text, model: "flash"))
        let moved = try XCTUnwrap(TTSAudioStore.localURL(text: newText, model: "flash"))
        // 実体はリネームのみで内容が保たれる
        XCTAssertEqual(try Data(contentsOf: moved), data)
    }

    func testRekeyLocalFileWithoutOldFileDoesNothing() {
        TTSAudioStore.rekeyLocalFile(oldText: text, newText: text + " new", model: "flash")
        XCTAssertNil(TTSAudioStore.localURL(text: text + " new", model: "flash"))
    }

    func testRekeyLocalFileKeepsNewerFileWhenBothExist() throws {
        let newText = text + "\n\nrekeyed"
        let newerData = Data("newer wav bytes".utf8)
        try TTSAudioStore.save(data: data, text: text, model: "flash")
        try TTSAudioStore.save(data: newerData, text: newText, model: "flash")

        TTSAudioStore.rekeyLocalFile(oldText: text, newText: newText, model: "flash")

        // 旧ファイルは消え、新キー側は上書きされず新しい方が残る
        XCTAssertNil(TTSAudioStore.localURL(text: text, model: "flash"))
        let kept = try XCTUnwrap(TTSAudioStore.localURL(text: newText, model: "flash"))
        XCTAssertEqual(try Data(contentsOf: kept), newerData)
    }

    func testRekeyLocalFileIsIdempotent() throws {
        let newText = text + "\n\nrekeyed"
        try TTSAudioStore.save(data: data, text: text, model: "flash")

        TTSAudioStore.rekeyLocalFile(oldText: text, newText: newText, model: "flash")
        // 2回目（移行リトライ相当）でも壊れない
        TTSAudioStore.rekeyLocalFile(oldText: text, newText: newText, model: "flash")

        let moved = try XCTUnwrap(TTSAudioStore.localURL(text: newText, model: "flash"))
        XCTAssertEqual(try Data(contentsOf: moved), data)
    }
}
