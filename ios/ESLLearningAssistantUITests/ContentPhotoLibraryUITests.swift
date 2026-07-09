import XCTest

/// 写真の横断一覧（Content タブの Photos セグメント、Phase 2）の導線を写真ライブラリ非依存で検証する。
/// 実際の取り込みは PHPicker / カメラ（OS側UI）を経由し決定的に駆動しづらいため、ここでは
/// (1) Photos セグメントが開けて取り込みの入口（＋ボタン・空状態）が出ること、
/// (2) レッスンが無いときは Capture シートが案内を出すこと、
/// (3) レッスンがあるときは Capture シートにレッスン選択と取り込みボタンが出ること、
/// までを確認する。取り込み→OCRの状態遷移は既存の testClassLessonCaptureFlow で担保。
final class ContentPhotoLibraryUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testPhotosSegmentShowsCaptureEntryPoints() throws {
        let app = XCUIApplication()
        app.launch()

        clearAllData(app)

        // 写真ライブラリは Content タブの Photos セグメント（既定選択）にある
        app.selectTab("Content")
        XCTAssertTrue(app.navigationBars["Content"].waitForExistence(timeout: 5))
        let photosSegment = app.segmentedControls.buttons["Photos"]
        XCTAssertTrue(photosSegment.waitForExistence(timeout: 5))
        photosSegment.tap()

        // ツールバーの追加ボタンと、空状態の追加導線が出る
        XCTAssertTrue(app.buttons["photoAddButton"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No photos yet"].exists)
        XCTAssertTrue(app.buttons["Add Photo"].exists)
        attach(app, "32-photos-segment-empty")

        // レッスンが1つも無い状態では、Capture シートは案内を出す（写真はレッスン必須）
        app.buttons["photoAddButton"].tap()
        XCTAssertTrue(app.staticTexts["No lessons yet"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Choose Photos"].exists)
        attach(app, "33-photos-capture-no-lesson")
        app.navigationBars.buttons["Close"].tap()
    }

    func testCaptureSheetShowsLessonPickerWhenLessonExists() throws {
        let app = XCUIApplication()
        app.launch()

        clearAllData(app)

        // クラスとレッスンを作成する
        app.tabBars.buttons["Lessons"].tap()
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

        // Photos セグメントの「+」で Capture シートを開くと、レッスン選択（既定=最新）と
        // ライブラリ取り込みボタンが出る（カメラはシミュレータ非対応のため Take Photo は見ない）
        app.selectTab("Content")
        let photosSegment = app.segmentedControls.buttons["Photos"]
        XCTAssertTrue(photosSegment.waitForExistence(timeout: 5))
        photosSegment.tap()
        XCTAssertTrue(app.buttons["photoAddButton"].waitForExistence(timeout: 5))
        app.buttons["photoAddButton"].tap()

        XCTAssertTrue(app.buttons["captureLessonPicker"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Choose Photos"].exists)
        attach(app, "34-photos-capture-with-lesson")
        app.navigationBars.buttons["Close"].tap()
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
