import XCTest

/// 作文タブの下書きフロー（ネットワーク不要の範囲）を検証する。
/// 添削（Review）の実通信は対象外で、タブ遷移・エディタ入力・ボタン活性・空作文の掃除を確認する。
final class CompositionUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCompositionDraftFlow() throws {
        let app = XCUIApplication()
        app.launch()

        clearAllData(app)

        // 作文タブ: 初期は空状態
        app.tabBars.buttons["Writing"].tap()
        XCTAssertTrue(app.staticTexts["No Writing Yet"].waitForExistence(timeout: 5))
        attach(app, "30-writing-empty")

        // 新規作成 → 詳細（新規）へ遷移。両欄が空なので Review は無効
        app.buttons["compositionAddButton"].tap()
        let english = app.textViews["compositionEnglishEditor"]
        XCTAssertTrue(english.waitForExistence(timeout: 5))
        let reviewButton = app.buttons["compositionReviewButton"]
        XCTAssertTrue(reviewButton.waitForExistence(timeout: 5))
        XCTAssertFalse(reviewButton.isEnabled, "両欄が空のとき Review は無効であるべき")

        // 英文だけ入力してもまだ無効
        english.tap()
        english.typeText("I go to school yesterday and meet my friend.")
        XCTAssertFalse(reviewButton.isEnabled, "日本語が空のとき Review は無効であるべき")

        // 日本語（意図）も入力すると有効になる
        let japanese = app.textViews["compositionJapaneseEditor"]
        japanese.tap()
        japanese.typeText("昨日学校に行って友達に会った。")
        XCTAssertTrue(reviewButton.isEnabled, "両欄が埋まると Review は有効であるべき")
        attach(app, "31-writing-ready-to-review")

        // 一覧に戻ると本文入りの作文が1件残る
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let row = app.staticTexts["I go to school yesterday and meet my friend."]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        attach(app, "32-writing-list-has-one")

        // 空のまま作成して戻ると、空作文は掃除されて増えない
        app.buttons["compositionAddButton"].tap()
        XCTAssertTrue(english.waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        // 空作文は掃除されるため、プレースホルダ行（"New Composition"）は残らない
        XCTAssertFalse(
            app.staticTexts["New Composition"].exists,
            "空作文は保存されず、プレースホルダ行が残らないべき"
        )
        attach(app, "33-writing-empty-draft-discarded")
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

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
