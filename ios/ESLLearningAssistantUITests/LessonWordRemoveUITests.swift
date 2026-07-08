import XCTest

final class LessonWordRemoveUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testSwipeRemoveUnlinksWordFromLessonOnly() throws {
        let app = XCUIApplication()
        // 正規化は素通し（canonical）に固定し、Add 時にネットワークへ出ないようにする
        app.launchArguments += ["-uiTestStubWordNormalize", "canonical"]
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

        // レッスンに単語を追加する（レッスン画面に留まる）
        addWordToLesson(app, text: "greeting")

        // Wordsタブの一覧を左スワイプしても Delete ボタンは出ない（単語本体のスワイプ削除は無し）。
        app.tabBars.buttons["Words"].tap()
        XCTAssertTrue(app.staticTexts["greeting"].waitForExistence(timeout: 5))
        // スワイプアクションが無い行では横パンが行タップ扱いになり詳細へ遷移するため、
        // 「Delete が現れない」ことを主張点にし、遷移していたら一覧へ戻す
        let wordCell = app.cells.firstMatch
        wordCell.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
            .press(forDuration: 0.2, thenDragTo: wordCell.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)))
        XCTAssertFalse(app.buttons["Delete"].waitForExistence(timeout: 2))
        attach(app, "60-words-tab-no-swipe-delete")
        if app.navigationBars["greeting"].exists {
            app.buttons["BackButton"].tap()
            XCTAssertTrue(app.staticTexts["greeting"].waitForExistence(timeout: 5))
        }

        // Lessonsタブに戻り、Wordsに反映されていることを確認する
        app.tabBars.buttons["Lessons"].tap()
        scrollTo(app, staticText: "greeting")
        XCTAssertTrue(app.staticTexts["Words (1)"].exists)

        // スワイプで Remove ボタンを出してタップする
        app.staticTexts["greeting"].swipeLeft()
        let removeButton = app.buttons["Remove"]
        XCTAssertTrue(removeButton.waitForExistence(timeout: 5))
        attach(app, "61-swipe-remove-button")
        removeButton.tap()

        // レッスンのWordsから消える
        XCTAssertTrue(app.staticTexts["Words (0)"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No words yet"].exists)
        attach(app, "62-lesson-word-removed")

        // Wordsタブの一覧には単語本体が残っている
        app.tabBars.buttons["Words"].tap()
        XCTAssertTrue(app.staticTexts["greeting"].waitForExistence(timeout: 5))
        attach(app, "63-words-list-still-has-word")

        // 再起動してもリンク解除と単語本体が維持されている（明示 save の確認）
        app.terminate()
        app.launch()
        app.tabBars.buttons["Lessons"].tap()
        XCTAssertTrue(app.staticTexts["Words (0)"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Words"].tap()
        XCTAssertTrue(app.staticTexts["greeting"].waitForExistence(timeout: 5))
        attach(app, "64-persisted-after-relaunch")

        // 外した単語を同じレッスンに再リンクできる（追加後はレッスン画面に留まる）
        app.tabBars.buttons["Lessons"].tap()
        addWordToLesson(app, text: "greeting")
        XCTAssertTrue(app.staticTexts["Words (1)"].waitForExistence(timeout: 5))
        scrollTo(app, staticText: "greeting")
        XCTAssertTrue(app.staticTexts["greeting"].exists)
        attach(app, "65-relinked")
    }

    /// LessonsタブのAdd Wordボタンからレッスン固定で単語を追加する（追加後はレッスン画面に留まる）
    private func addWordToLesson(_ app: XCUIApplication, text: String) {
        let lessonWordAddButton = app.buttons["lessonWordAddButton"]
        scrollTo(app, element: lessonWordAddButton)
        lessonWordAddButton.tap()
        let wordTextField = app.textFields["wordTextField"]
        XCTAssertTrue(wordTextField.waitForExistence(timeout: 5))
        wordTextField.tap()
        wordTextField.typeText(text)
        app.navigationBars.buttons["Add"].tap()
        XCTAssertTrue(app.staticTexts[text].waitForExistence(timeout: 5))
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
