import XCTest

final class ESLLearningAssistantUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testTabsAreVisible() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["ホーム"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["単語帳"].exists)
        XCTAssertTrue(app.tabBars.buttons["問題"].exists)
        XCTAssertTrue(app.tabBars.buttons["設定"].exists)
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
        attach(app, "01-home-empty-class")

        let addClassButton = app.buttons["homeAddClassButton"]
        XCTAssertTrue(addClassButton.waitForExistence(timeout: 5))
        addClassButton.tap()

        let switcherAddClassButton = app.buttons["switcherAddClassButton"]
        XCTAssertTrue(switcherAddClassButton.waitForExistence(timeout: 5))
        switcherAddClassButton.tap()

        let classNameField = app.alerts.textFields.firstMatch
        XCTAssertTrue(classNameField.waitForExistence(timeout: 5))
        classNameField.typeText("ESL Beginner A")
        app.alerts.buttons["追加"].tap()
        attach(app, "02-switcher-class-added")

        app.buttons["閉じる"].tap()
        attach(app, "03-home-empty-lesson")

        let addLessonButton = app.buttons["新しいレッスン"]
        XCTAssertTrue(addLessonButton.waitForExistence(timeout: 5))
        addLessonButton.tap()

        let lessonNameField = app.alerts.textFields.firstMatch
        XCTAssertTrue(lessonNameField.waitForExistence(timeout: 5))
        lessonNameField.typeText("Unit 1 Greetings")
        app.alerts.buttons["追加"].tap()
        attach(app, "04-home-with-lesson")

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

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
