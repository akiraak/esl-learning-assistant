import XCTest

final class ESLLearningAssistantUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testTabsAreVisible() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["Lessons"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Words"].exists)
        XCTAssertTrue(app.tabBars.buttons["Settings"].exists)
    }

    func testWarmUpPhotosLibrary() throws {
        let photos = XCUIApplication(bundleIdentifier: "com.apple.mobileslideshow")
        photos.launch()
        let continueButton = photos.buttons["続ける"]
        if continueButton.waitForExistence(timeout: 5) {
            continueButton.tap()
        }
        _ = photos.collectionViews.cells.firstMatch.waitForExistence(timeout: 60)
        photos.terminate()
    }

    func testClassLessonCaptureFlow() throws {
        let app = XCUIApplication()
        app.launch()
        attach(app, "01-lesson-empty-class")

        let addClassButton = app.buttons["lessonAddClassButton"]
        XCTAssertTrue(addClassButton.waitForExistence(timeout: 5))
        addClassButton.tap()

        let switcherAddClassButton = app.buttons["switcherAddClassButton"]
        XCTAssertTrue(switcherAddClassButton.waitForExistence(timeout: 5))
        switcherAddClassButton.tap()

        let classNameField = app.textFields["classNameField"]
        XCTAssertTrue(classNameField.waitForExistence(timeout: 5))
        classNameField.tap()
        classNameField.typeText("ESL Beginner A")
        app.navigationBars.buttons["追加"].tap()
        attach(app, "02-switcher-class-added")

        let addLessonButton = app.buttons["switcherAddLessonButton"]
        XCTAssertTrue(addLessonButton.waitForExistence(timeout: 5))
        addLessonButton.tap()

        let lessonTitleField = app.textFields["lessonTitleField"]
        XCTAssertTrue(lessonTitleField.waitForExistence(timeout: 5))
        lessonTitleField.tap()
        lessonTitleField.typeText("Unit 1 Greetings")
        app.navigationBars.buttons["追加"].tap()
        attach(app, "04-lesson-with-lesson")

        let capturePhotoButton = app.buttons["写真を追加"]
        XCTAssertTrue(capturePhotoButton.waitForExistence(timeout: 5))
        capturePhotoButton.tap()
        attach(app, "05-capture-sheet")

        let pickPhotoButton = app.buttons["写真を選択"]
        XCTAssertTrue(pickPhotoButton.waitForExistence(timeout: 5))
        pickPhotoButton.tap()

        // PHPicker is hosted out-of-process: its cells aren't queryable via `app`'s
        // accessibility tree, so tap by screen coordinate instead of element lookup.
        Thread.sleep(forTimeInterval: 3)
        attach(app, "06-photos-picker")
        let photoCellCoordinate = app.windows.firstMatch.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6)
        )
        photoCellCoordinate.tap()

        if app.navigationBars.buttons["追加"].waitForExistence(timeout: 3) {
            app.navigationBars.buttons["追加"].tap()
        }

        let ocrHeading = app.staticTexts["OCR結果（英語）"]
        XCTAssertTrue(ocrHeading.waitForExistence(timeout: 10))
        attach(app, "07-photo-detail")
    }

    func testWordAddFlow() throws {
        let app = XCUIApplication()
        app.launch()

        // クラス・レッスンを用意する（未作成の場合のみ）
        let addClassButton = app.buttons["lessonAddClassButton"]
        if addClassButton.waitForExistence(timeout: 5) {
            addClassButton.tap()
            app.buttons["switcherAddClassButton"].tap()
            let classNameField = app.textFields["classNameField"]
            XCTAssertTrue(classNameField.waitForExistence(timeout: 5))
            classNameField.tap()
            classNameField.typeText("ESL Beginner A")
            app.navigationBars.buttons["追加"].tap()
            let addLessonButton = app.buttons["switcherAddLessonButton"]
            XCTAssertTrue(addLessonButton.waitForExistence(timeout: 5))
            addLessonButton.tap()
            let lessonTitleField = app.textFields["lessonTitleField"]
            XCTAssertTrue(lessonTitleField.waitForExistence(timeout: 5))
            lessonTitleField.tap()
            lessonTitleField.typeText("Unit 1 Greetings")
            app.navigationBars.buttons["追加"].tap()
        }

        // 単語タブ: レッスン指定ありで追加
        app.tabBars.buttons["Words"].tap()
        attach(app, "10-words-tab")

        app.buttons["wordAddButton"].tap()
        let textField = app.textFields["見出し語（例: apple）"]
        XCTAssertTrue(textField.waitForExistence(timeout: 5))
        textField.tap()
        textField.typeText("apple")
        let translationField = app.textFields["訳語（例: りんご）"]
        translationField.tap()
        translationField.typeText("ringo")

        app.buttons["wordLessonPicker"].tap()
        let lessonOption = app.buttons["ESL Beginner A / Unit 1 Greetings"]
        XCTAssertTrue(lessonOption.waitForExistence(timeout: 5))
        lessonOption.tap()
        attach(app, "11-word-add-form-with-lesson")
        app.navigationBars.buttons["追加"].tap()

        XCTAssertTrue(app.staticTexts["apple"].waitForExistence(timeout: 5))
        attach(app, "12-words-list")

        // 単語タブ: レッスン指定なしでも追加できる
        app.buttons["wordAddButton"].tap()
        XCTAssertTrue(textField.waitForExistence(timeout: 5))
        textField.tap()
        textField.typeText("book")
        translationField.tap()
        translationField.typeText("hon")
        app.navigationBars.buttons["追加"].tap()
        XCTAssertTrue(app.staticTexts["book"].waitForExistence(timeout: 5))

        // 単語詳細: 登場レッスンが表示される
        app.staticTexts["apple"].tap()
        XCTAssertTrue(app.staticTexts["Unit 1 Greetings"].waitForExistence(timeout: 5))
        attach(app, "13-word-detail")
        app.navigationBars.buttons.firstMatch.tap()

        // レッスンタブ: 単語セクションに反映される
        app.tabBars.buttons["Lessons"].tap()
        XCTAssertTrue(app.staticTexts["apple"].waitForExistence(timeout: 5))
        attach(app, "14-lesson-with-word")
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
