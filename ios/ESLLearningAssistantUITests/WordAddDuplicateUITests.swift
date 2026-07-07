import XCTest

/// 既存単語を「Add Word」フォームで弾く挙動の回帰テスト。
/// 同綴り（大文字小文字を含む）の単語を入力すると、説明文が出て Add ボタンが無効化される。
final class WordAddDuplicateUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testDuplicateWordIsRejectedInAddForm() throws {
        let app = XCUIApplication()
        // 正規化は素通し（canonical）に固定し、Add 時にネットワークへ出ないようにする
        app.launchArguments += ["-uiTestStubWordNormalize", "canonical"]
        app.launch()

        // 前回実行のデータが残っていると初期状態から始められないため、先に全クリアする
        clearAllData(app)
        app.tabBars.buttons["Words"].tap()

        // まず "apple" を1件追加する（新規語なので通常どおり登録できる）
        addWord(app, text: "apple")
        XCTAssertTrue(app.staticTexts["apple"].waitForExistence(timeout: 5))

        // 同じ "apple" を再入力 → 説明文が出て Add が無効
        openAddSheet(app)
        let wordTextField = app.textFields["wordTextField"]
        XCTAssertTrue(wordTextField.waitForExistence(timeout: 5))
        wordTextField.tap()
        wordTextField.typeText("apple")

        let warning = app.staticTexts["wordDuplicateWarning"]
        XCTAssertTrue(warning.waitForExistence(timeout: 3), "重複警告の説明文が表示されるべき")
        let addButton = app.navigationBars.buttons["Add"]
        XCTAssertTrue(addButton.exists)
        XCTAssertFalse(addButton.isEnabled, "重複時は Add ボタンが無効であるべき")
        app.navigationBars.buttons["Cancel"].tap()

        // 大文字違いの "Apple" でも case-insensitive に弾かれる
        XCTAssertTrue(wordTextField.waitForNonExistence(timeout: 5))
        openAddSheet(app)
        XCTAssertTrue(wordTextField.waitForExistence(timeout: 5))
        wordTextField.tap()
        wordTextField.typeText("Apple")
        XCTAssertTrue(warning.waitForExistence(timeout: 3), "大文字違いでも重複として弾かれるべき")
        XCTAssertFalse(app.navigationBars.buttons["Add"].isEnabled)
        app.navigationBars.buttons["Cancel"].tap()
    }

    // MARK: - Helpers

    private func openAddSheet(_ app: XCUIApplication) {
        let addWordButton = app.buttons["wordAddButton"]
        XCTAssertTrue(addWordButton.waitForExistence(timeout: 5))
        addWordButton.tap()
    }

    private func addWord(_ app: XCUIApplication, text: String) {
        openAddSheet(app)
        let wordTextField = app.textFields["wordTextField"]
        XCTAssertTrue(wordTextField.waitForExistence(timeout: 5))
        wordTextField.tap()
        wordTextField.typeText(text)
        app.navigationBars.buttons["Add"].tap()
        XCTAssertTrue(wordTextField.waitForNonExistence(timeout: 5))
    }

    private func clearAllData(_ app: XCUIApplication) {
        app.tabBars.buttons["Settings"].tap()
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
