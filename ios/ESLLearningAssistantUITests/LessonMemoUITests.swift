import XCTest

final class LessonMemoUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLessonMemoFlow() throws {
        let app = XCUIApplication()
        app.launch()

        // 前回実行のデータが残っていると空メモ状態から始められないため、先に全クリアする
        clearAllData(app)
        app.tabBars.buttons["Lessons"].tap()

        // クラスとレッスンを作成する
        createClassAndTodayLesson(app)

        // Memoセクション: 初期状態はプレースホルダ表示
        scrollTo(app, staticText: "No memo yet")
        XCTAssertTrue(app.staticTexts["No memo yet"].exists)
        attach(app, "20-memo-empty")

        // 空白のみのメモは保存してもメモなし扱いのまま（trim → nil）
        let memoButton = app.buttons["lessonMemoButton"]
        memoButton.tap()
        let editor = app.textViews["lessonMemoEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText("   ")
        app.navigationBars.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["No memo yet"].waitForExistence(timeout: 5))
        attach(app, "21-memo-whitespace-stays-empty")

        // 複数行のメモを入力して保存する
        memoButton.tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText("Homework: page 12\nReview greetings vocabulary")
        attach(app, "22-memo-editing")
        app.navigationBars.buttons["Save"].tap()

        let savedMemo = app.staticTexts["Homework: page 12\nReview greetings vocabulary"]
        XCTAssertTrue(savedMemo.waitForExistence(timeout: 5))
        attach(app, "23-memo-saved")

        // アプリを再起動してもメモが保持される
        app.terminate()
        app.launch()
        scrollTo(app, staticText: "Homework: page 12\nReview greetings vocabulary")
        XCTAssertTrue(savedMemo.waitForExistence(timeout: 5))
        attach(app, "24-memo-persists-after-relaunch")
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

    /// 指定テキストが見えるまで下方向へスクロールする（最大5回）
    private func scrollTo(_ app: XCUIApplication, staticText label: String) {
        for _ in 0..<5 {
            if app.staticTexts[label].waitForExistence(timeout: 2),
               app.staticTexts[label].isHittable {
                return
            }
            app.swipeUp()
        }
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
