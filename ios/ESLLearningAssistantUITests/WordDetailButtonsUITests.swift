import XCTest

final class WordDetailButtonsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testDeleteAndRegenerateButtonsAtBottomOfWordDetail() throws {
        let app = XCUIApplication()
        app.launch()

        // 前回実行のデータが残っていると初期状態から始められないため、先に全クリアする
        clearAllData(app)
        app.tabBars.buttons["Lessons"].tap()

        // クラスとレッスンを作成する
        let addClassButton = app.buttons["lessonAddClassButton"]
        XCTAssertTrue(addClassButton.waitForExistence(timeout: 5))
        addClassButton.tap()
        app.buttons["switcherAddClassButton"].tap()
        let classNameField = app.textFields["classNameField"]
        XCTAssertTrue(classNameField.waitForExistence(timeout: 5))
        classNameField.tap()
        classNameField.typeText("ESL Beginner A")
        app.navigationBars.buttons["Add"].tap()
        let addLessonButton = app.buttons["switcherAddLessonButton"]
        XCTAssertTrue(addLessonButton.waitForExistence(timeout: 5))
        addLessonButton.tap()
        let lessonTitleField = app.textFields["lessonTitleField"]
        XCTAssertTrue(lessonTitleField.waitForExistence(timeout: 5))
        lessonTitleField.tap()
        lessonTitleField.typeText("Unit 1 Greetings")
        app.navigationBars.buttons["Add"].tap()

        // レッスンに単語を追加する（Wordsタブに切り替わる）
        let lessonWordAddButton = app.buttons["lessonWordAddButton"]
        scrollTo(app, element: lessonWordAddButton)
        lessonWordAddButton.tap()
        let wordTextField = app.textFields["wordTextField"]
        XCTAssertTrue(wordTextField.waitForExistence(timeout: 5))
        wordTextField.tap()
        wordTextField.typeText("greeting")
        app.navigationBars.buttons["Add"].tap()
        XCTAssertTrue(app.staticTexts["greeting"].waitForExistence(timeout: 5))

        // 詳細画面を開く
        app.staticTexts["greeting"].tap()
        XCTAssertTrue(app.navigationBars["greeting"].waitForExistence(timeout: 5))

        // 下部に再生成・削除ボタンが両方ある
        let regenerateButton = app.buttons["wordRegenerateButton"]
        let deleteButton = app.buttons["wordDeleteButton"]
        scrollTo(app, element: deleteButton)
        XCTAssertTrue(regenerateButton.exists)
        XCTAssertTrue(deleteButton.exists)
        attach(app, "30-detail-bottom-buttons")

        // 再生成をタップすると生成が走る（API Secret未設定のため最終的にfailedになる）
        regenerateButton.tap()
        let failedLabel = app.staticTexts["wordAIInfoFailedLabel"]
        XCTAssertTrue(failedLabel.waitForExistence(timeout: 15))
        attach(app, "31-regenerate-ran-and-failed")

        // 確認ダイアログ（ボタンにアンカーされたポップオーバー型、Cancelボタンなし）を
        // 外側タップで閉じると何も起きない
        scrollTo(app, element: deleteButton)
        deleteButton.tap()
        let dialogTitle = app.staticTexts["Delete this word?"]
        XCTAssertTrue(dialogTitle.waitForExistence(timeout: 5))
        attach(app, "32-delete-confirmation")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6)).tap()
        XCTAssertTrue(dialogTitle.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["greeting"].exists)

        // 削除を実行すると一覧に戻り、単語が消えている
        scrollTo(app, element: deleteButton)
        deleteButton.tap()
        let confirmDelete = app.buttons["Delete"]
        XCTAssertTrue(confirmDelete.waitForExistence(timeout: 5))
        confirmDelete.tap()
        XCTAssertTrue(app.staticTexts["No Words"].waitForExistence(timeout: 5))
        attach(app, "33-word-deleted-from-list")

        // レッスンのWordsからも消えている（cascadeでリンクも削除）
        app.tabBars.buttons["Lessons"].tap()
        XCTAssertTrue(app.staticTexts["Words (0)"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No words yet"].exists)
        attach(app, "34-lesson-words-empty")
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

    /// 指定要素が見えるまで下方向へスクロールする（最大5回）
    private func scrollTo(_ app: XCUIApplication, element: XCUIElement) {
        for _ in 0..<5 {
            if element.waitForExistence(timeout: 2), element.isHittable {
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
