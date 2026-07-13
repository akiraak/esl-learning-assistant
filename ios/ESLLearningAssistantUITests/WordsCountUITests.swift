import XCTest

/// Words タブの登録単語数表示: 一覧のセクション見出しに「Words (N)」を出し、追加のたびに更新される。
/// 正規化サービスは launch 引数のスタブ（`canonical`）で差し替え、確認ダイアログなしで即登録させる。
final class WordsCountUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 単語を追加するごとに見出しの件数が 1 → 2 と増える
    func testCountHeaderUpdatesOnAdd() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestStubWordNormalize", "canonical"]
        app.launch()
        clearAllData(app)
        app.tabBars.buttons["Words"].tap()

        typeWordAndTapAdd(app, text: "apple")
        XCTAssertTrue(app.staticTexts["apple"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Words (1)"].waitForExistence(timeout: 5), "登録総数の見出しが出るべき")

        typeWordAndTapAdd(app, text: "banana")
        XCTAssertTrue(app.staticTexts["banana"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Words (2)"].waitForExistence(timeout: 5), "追加後に件数が更新されるべき")
    }

    // MARK: - Helpers

    private func typeWordAndTapAdd(_ app: XCUIApplication, text: String) {
        app.buttons["wordAddButton"].tap()
        let wordTextField = app.textFields["wordTextField"]
        XCTAssertTrue(wordTextField.waitForExistence(timeout: 5))
        wordTextField.tap()
        wordTextField.typeText(text)
        app.navigationBars.buttons["Add"].tap()
    }

    private func clearAllData(_ app: XCUIApplication) {
        app.selectTab("Settings")
        let clearButton = app.buttons["Delete All Data"]
        XCTAssertTrue(clearButton.waitForExistence(timeout: 5))
        app.swipeUp()
        clearButton.tap()
        let deleteButton = app.buttons["Delete"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 5))
        deleteButton.tap()
        XCTAssertTrue(deleteButton.waitForNonExistence(timeout: 5))
    }
}
