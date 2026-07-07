import XCTest

/// 入力単語の自動正規化（Phase 2）: Add Word フォームで訂正候補が出たときの確認ダイアログの挙動。
/// 正規化サービスは launch 引数のスタブ（`-uiTestStubWordNormalize`）で差し替え、ネットワークに
/// 依存せず決定的に検証する。スタブ "inflected|run|..." により、どの入力も原形 "run" を提案する。
final class WordAddNormalizationUITests: XCTestCase {
    private let inflectedStub = "inflected|run|「ran」は動詞「run」の過去形です"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 主ボタンで原形「run」が登録される（"ran" ではない）
    func testConfirmRegistersLemma() throws {
        let app = launchApp(stub: inflectedStub)
        clearAllData(app)
        app.tabBars.buttons["Words"].tap()

        typeWordAndTapAdd(app, text: "ran")

        let confirmButton = app.sheets.buttons["Register “run”"]
        XCTAssertTrue(confirmButton.waitForExistence(timeout: 5), "原形登録の主ボタンが出るべき")
        XCTAssertTrue(app.sheets.buttons["Keep “ran”"].exists, "入力形の逃げ道ボタンも出るべき")
        confirmButton.tap()

        XCTAssertTrue(app.staticTexts["run"].waitForExistence(timeout: 5), "原形 run が一覧に出るべき")
        XCTAssertFalse(app.staticTexts["ran"].exists, "入力形 ran は登録されないべき")
    }

    /// 逃げ道ボタンで入力形「ran」がそのまま登録される
    func testEscapeRegistersInput() throws {
        let app = launchApp(stub: inflectedStub)
        clearAllData(app)
        app.tabBars.buttons["Words"].tap()

        typeWordAndTapAdd(app, text: "ran")

        let escapeButton = app.sheets.buttons["Keep “ran”"]
        XCTAssertTrue(escapeButton.waitForExistence(timeout: 5))
        escapeButton.tap()

        XCTAssertTrue(app.staticTexts["ran"].waitForExistence(timeout: 5), "入力形 ran が一覧に出るべき")
    }

    /// Cancel で登録されず、フォームに留まる
    func testCancelKeepsFormWithoutRegistering() throws {
        let app = launchApp(stub: inflectedStub)
        clearAllData(app)
        app.tabBars.buttons["Words"].tap()

        typeWordAndTapAdd(app, text: "ran")

        // ダイアログが出たことを主ボタンで確認する
        XCTAssertTrue(app.sheets.buttons["Register “run”"].waitForExistence(timeout: 5))

        // キャンセル相当の操作でダイアログを閉じる（action sheet の Cancel ボタン、または
        // popover 表示時は外側タップ。どちらも .cancel 相当で登録は起きない）
        dismissDialog(app)

        // ダイアログが閉じてフォームに留まる（入力欄が残る）
        let wordTextField = app.textFields["wordTextField"]
        XCTAssertTrue(wordTextField.waitForExistence(timeout: 5))

        // フォームを閉じて一覧に何も登録されていないことを確認する
        app.navigationBars.buttons["Cancel"].tap()
        XCTAssertTrue(wordTextField.waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["run"].exists)
        XCTAssertFalse(app.staticTexts["ran"].exists)
    }

    /// canonical（訂正しない）入力では確認ダイアログを出さず即登録する（回帰）
    func testCanonicalRegistersWithoutDialog() throws {
        let app = launchApp(stub: "canonical")
        clearAllData(app)
        app.tabBars.buttons["Words"].tap()

        typeWordAndTapAdd(app, text: "apple")

        XCTAssertTrue(app.staticTexts["apple"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.sheets.buttons["Register “apple”"].exists, "canonical では確認ダイアログを出さない")
    }

    // MARK: - Helpers

    private func launchApp(stub: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestStubWordNormalize", stub]
        app.launch()
        return app
    }

    /// 確認ダイアログをキャンセル相当で閉じる。iPhone の action sheet では別 ScrollView 内の
    /// Cancel ボタン、popover 表示では外側の PopoverDismissRegion をタップする（環境で表示形式が変わる）。
    private func dismissDialog(_ app: XCUIApplication) {
        let cancelButton = app.scrollViews.buttons["Cancel"]
        if cancelButton.waitForExistence(timeout: 2) {
            cancelButton.tap()
            return
        }
        let dismissRegion = app.otherElements["PopoverDismissRegion"]
        if dismissRegion.waitForExistence(timeout: 2) {
            dismissRegion.tap()
            return
        }
        // フォールバック: ナビバー以外の Cancel
        app.buttons["Cancel"].firstMatch.tap()
    }

    private func typeWordAndTapAdd(_ app: XCUIApplication, text: String) {
        app.buttons["wordAddButton"].tap()
        let wordTextField = app.textFields["wordTextField"]
        XCTAssertTrue(wordTextField.waitForExistence(timeout: 5))
        wordTextField.tap()
        wordTextField.typeText(text)
        app.navigationBars.buttons["Add"].tap()
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
