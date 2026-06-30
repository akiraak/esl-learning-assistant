import XCTest

final class ESLLearningAssistantUITests: XCTestCase {
    func testTabsAreVisible() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["撮影"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["単語帳"].exists)
        XCTAssertTrue(app.tabBars.buttons["問題"].exists)
        XCTAssertTrue(app.tabBars.buttons["設定"].exists)
    }
}
