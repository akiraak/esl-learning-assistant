import XCTest

final class LessonWordAddUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testAddWordFromLessonPage() throws {
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

        // Wordsセクションの Add Word ボタンをタップする
        let lessonWordAddButton = app.buttons["lessonWordAddButton"]
        scrollTo(app, element: lessonWordAddButton)
        attach(app, "10-lesson-words-section")
        lessonWordAddButton.tap()

        // Lessonsタブに留まったまま、単語追加シートが開く
        let wordTextField = app.textFields["wordTextField"]
        XCTAssertTrue(wordTextField.waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Lessons"].isSelected)

        // 単語入力欄には開いた直後からフォーカスが当たっている
        XCTAssertTrue(waitForKeyboardFocus(wordTextField))

        // レッスンは固定表示（Pickerは存在しない＝変更不可）
        // LabeledContent はラベルと値を1つのアクセシビリティ要素に結合するため identifier で参照する
        let fixedLabel = app.staticTexts["wordLessonFixedLabel"]
        XCTAssertTrue(fixedLabel.waitForExistence(timeout: 5))
        XCTAssertTrue(fixedLabel.label.contains("ESL Beginner A / Unit 1 Greetings"))
        XCTAssertFalse(app.buttons["wordLessonPicker"].exists)
        XCTAssertTrue(app.staticTexts["This word will be linked to this lesson."].exists)
        attach(app, "11-add-sheet-lesson-fixed")

        // 単語を追加する
        wordTextField.tap()
        wordTextField.typeText("greeting")
        app.navigationBars.buttons["Add"].tap()

        // シートが閉じてレッスン画面に戻り、そのレッスンの Words に反映されている
        XCTAssertTrue(wordTextField.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Lessons"].isSelected)
        scrollTo(app, staticText: "greeting")
        XCTAssertTrue(app.staticTexts["Words (1)"].exists)
        XCTAssertTrue(app.staticTexts["greeting"].exists)
        attach(app, "12-lesson-words-reflected")

        // Wordsタブの一覧にも追加されている
        app.tabBars.buttons["Words"].tap()
        XCTAssertTrue(app.staticTexts["greeting"].waitForExistence(timeout: 5))
        attach(app, "13-words-list-added")

        // 回帰確認: Wordsタブからの通常追加ではレッスンPickerが選択可能なまま
        app.buttons["wordAddButton"].tap()
        let picker = app.buttons["wordLessonPicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        attach(app, "14-normal-add-picker-still-selectable")
        app.navigationBars.buttons["Cancel"].tap()
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

    /// 要素にキーボードフォーカスが当たるまで待つ（シート表示アニメーション分の猶予を持たせる）
    private func waitForKeyboardFocus(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if element.value(forKey: "hasKeyboardFocus") as? Bool == true { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        } while Date() < deadline
        return false
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
