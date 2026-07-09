import XCTest
@testable import ESLLearningAssistant

final class TTSCacheRekeyMigrationTests: XCTestCase {
    // 複数ブロック（見出し+段落）の Markdown だけがリキー対象になる
    func testTargetsPicksOnlyTextsWhoseKeyChanges() {
        let multiBlock = "# The Sun and the Wind\n\nThe north wind and the sun argued."
        let singleParagraph = "A single **paragraph** stays keyed the same."

        let targets = TTSCacheRekeyMigration.targets(markdownSources: [multiBlock, singleParagraph])

        XCTAssertEqual(targets.count, 1)
        XCTAssertEqual(targets[0].oldText, "The Sun and the WindThe north wind and the sun argued.")
        XCTAssertEqual(targets[0].newText, "The Sun and the Wind\n\nThe north wind and the sun argued.")
    }

    // 同じ原文（同じ教材を複数回取り込んだ場合など）は1件にまとめる
    func testTargetsDeduplicatesSameSource() {
        let multiBlock = "# Title\n\nBody paragraph."
        let targets = TTSCacheRekeyMigration.targets(markdownSources: [multiBlock, multiBlock])
        XCTAssertEqual(targets.count, 1)
    }

    func testTargetsWithEmptyOrSingleBlockSourcesIsEmpty() {
        let targets = TTSCacheRekeyMigration.targets(markdownSources: [
            "",
            "plain sentence",
            "**inline** only markup",
        ])
        XCTAssertTrue(targets.isEmpty)
    }
}
