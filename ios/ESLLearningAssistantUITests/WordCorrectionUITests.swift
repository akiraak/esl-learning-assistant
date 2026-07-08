import XCTest

/// 入力単語の自動正規化 Phase 4: 登録済み単語を WordDetailView から原形／正しい綴りへ後追いで訂正する。
/// 正規化サービスは launch 引数のスタブ（`-uiTestStubWordNormalize`）で差し替え、ネットワークに依存せず
/// 決定的に検証する。スタブ "inflected|run|..." により、どの入力も原形 "run" を提案する。
final class WordCorrectionUITests: XCTestCase {
    private let inflectedStub = "inflected|run|「ran」は動詞「run」の過去形です"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Correct Word → 確認ダイアログ → 原形 run へその場リネーム（衝突なし）。詳細タイトルと一覧が run に更新される。
    func testCorrectRenamesRegisteredWordToLemma() throws {
        let app = launchApp(stub: inflectedStub)
        clearAllData(app)
        app.tabBars.buttons["Words"].tap()

        // 逃げ道で入力形 "ran" をそのまま登録しておく（あとから訂正する対象）
        addWordKeepingInput(app, text: "ran")
        XCTAssertTrue(app.staticTexts["ran"].waitForExistence(timeout: 5))

        // 詳細を開く
        app.staticTexts["ran"].tap()
        XCTAssertTrue(app.navigationBars["ran"].waitForExistence(timeout: 5))

        // Correct Word をタップ → 確認ダイアログの主ボタンで原形 run に訂正
        tapCorrectWordAndConfirmToRun(app)

        // 衝突が無いのでその場リネーム: タイトルが run に更新される（詳細に留まる）
        XCTAssertTrue(app.navigationBars["run"].waitForExistence(timeout: 5), "タイトルが run に更新されるべき")

        // 一覧に戻ると run になっており旧綴り ran は消えている
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["run"].waitForExistence(timeout: 5), "一覧が run に更新されるべき")
        XCTAssertFalse(app.staticTexts["ran"].exists, "旧綴り ran は残らないべき")
    }

    /// 正規化形 run が既存語と一致する場合はマージ: 表示中の ran は削除され一覧へ戻り、run 1件に集約される。
    func testCorrectMergesIntoExistingWord() throws {
        let app = launchApp(stub: inflectedStub)
        clearAllData(app)
        app.tabBars.buttons["Words"].tap()

        // 既存語 "run" を登録（スタブは run を提案するが lemma==入力なので確認は出ず即登録）
        addWord(app, text: "run")
        XCTAssertTrue(app.staticTexts["run"].waitForExistence(timeout: 5))
        // 訂正対象 "ran" を逃げ道で登録
        addWordKeepingInput(app, text: "ran")
        XCTAssertTrue(app.staticTexts["ran"].waitForExistence(timeout: 5))

        // "ran" の詳細を開いて Correct Word → run へ訂正（既存 run と衝突 → マージ）
        app.staticTexts["ran"].tap()
        XCTAssertTrue(app.navigationBars["ran"].waitForExistence(timeout: 5))
        tapCorrectWordAndConfirmToRun(app)

        // マージで表示中の語が消えるため一覧へ戻る。ran は消え run に集約される
        XCTAssertTrue(app.staticTexts["ran"].waitForNonExistence(timeout: 5), "ran は削除されるべき")
        XCTAssertTrue(app.staticTexts["run"].waitForExistence(timeout: 5), "run に集約されるべき")
    }

    // MARK: - Helpers

    private func launchApp(stub: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestStubWordNormalize", stub]
        app.launch()
        return app
    }

    /// Correct Word をタップし、確認ダイアログの主ボタン「Correct to “run”」で確定する。
    private func tapCorrectWordAndConfirmToRun(_ app: XCUIApplication) {
        let correctButton = app.buttons["wordCorrectButton"]
        scrollTo(app, element: correctButton)
        correctButton.tap()
        let confirmButton = app.buttons["Correct to “run”"]
        XCTAssertTrue(confirmButton.waitForExistence(timeout: 5), "訂正の主ボタンが出るべき")
        confirmButton.tap()
    }

    /// Words タブの Add で単語を登録する（確認ダイアログが出ない canonical/一致ケース用）。
    private func addWord(_ app: XCUIApplication, text: String) {
        app.buttons["wordAddButton"].tap()
        let field = app.textFields["wordTextField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(text)
        app.navigationBars.buttons["Add"].tap()
    }

    /// 訂正候補が出る入力を、逃げ道「Keep “…”」で入力形のまま登録する。
    private func addWordKeepingInput(_ app: XCUIApplication, text: String) {
        app.buttons["wordAddButton"].tap()
        let field = app.textFields["wordTextField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(text)
        app.navigationBars.buttons["Add"].tap()
        let keepButton = app.sheets.buttons["Keep “\(text)”"]
        XCTAssertTrue(keepButton.waitForExistence(timeout: 5))
        keepButton.tap()
    }

    /// 指定要素が見えるまで下方向へスクロールする（最大5回）
    private func scrollTo(_ app: XCUIApplication, element: XCUIElement) {
        for _ in 0..<5 {
            if element.waitForExistence(timeout: 2), element.isHittable {
                return
            }
            app.swipeUp()
        }
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
