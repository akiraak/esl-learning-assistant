import XCTest

final class WordDetailButtonsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testDeleteAndRegenerateButtonsAtBottomOfWordDetail() throws {
        let app = XCUIApplication()
        // 正規化は素通し（canonical）に固定し、Add 時にネットワークへ出ないようにする
        app.launchArguments += ["-uiTestStubWordNormalize", "canonical"]
        app.launch()

        // 前回実行のデータが残っていると初期状態から始められないため、先に全クリアする
        clearAllData(app)
        app.tabBars.buttons["Lessons"].tap()

        // クラスとレッスンを作成する
        createClassAndTodayLesson(app)

        // レッスンに単語を追加する（レッスン画面に留まる）
        let lessonWordAddButton = app.buttons["lessonWordAddButton"]
        scrollTo(app, element: lessonWordAddButton)
        lessonWordAddButton.tap()
        let wordTextField = app.textFields["wordTextField"]
        XCTAssertTrue(wordTextField.waitForExistence(timeout: 5))
        wordTextField.tap()
        wordTextField.typeText("greeting")
        app.navigationBars.buttons["Add"].tap()
        XCTAssertTrue(app.staticTexts["greeting"].waitForExistence(timeout: 5))

        // レッスンのWords行をタップすると、レッスン画面のまま詳細画面が開く
        app.staticTexts["greeting"].tap()
        XCTAssertTrue(app.navigationBars["greeting"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Lessons"].isSelected)

        // 戻るとレッスン画面に戻る
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["greeting"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["greeting"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Lessons"].isSelected)
        attach(app, "29-back-to-lesson")

        // 再度詳細を開く
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

        // 削除を実行するとレッスン画面に戻り、Wordsから消えている（cascadeでリンクも削除）
        scrollTo(app, element: deleteButton)
        deleteButton.tap()
        let confirmDelete = app.buttons["Delete"]
        XCTAssertTrue(confirmDelete.waitForExistence(timeout: 5))
        confirmDelete.tap()
        XCTAssertTrue(app.staticTexts["Words (0)"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No words yet"].exists)
        attach(app, "33-lesson-words-empty")

        // Wordsタブの一覧からも消えている
        app.tabBars.buttons["Words"].tap()
        XCTAssertTrue(app.staticTexts["No Words"].waitForExistence(timeout: 5))
        attach(app, "34-words-list-empty")
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
