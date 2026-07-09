import XCTest

/// YouTube の横断一覧（Content タブの YouTube セグメント、Phase 3）の E2E 確認。
/// YouTube 追加は OS 側 UI を介さない（テキスト入力のみ）ため、写真と違い追加まで通しで検証できる。
/// (1) YouTube セグメントが開けて追加の入口（＋ボタン・空状態）が出ること、
/// (2) レッスンが無いときは追加シートが案内を出すこと、
/// (3) レッスンがあるときはシート内のレッスン選択（既定=最新）経由で追加でき、
///     一覧にレッスン名付きで反映され詳細へ遷移できること、を確認する。
final class ContentYouTubeLibraryUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testYouTubeSegmentShowsAddEntryPoints() throws {
        let app = XCUIApplication()
        app.launch()

        clearAllData(app)

        // YouTube ライブラリは Content タブの YouTube セグメントにある
        app.selectTab("Content")
        XCTAssertTrue(app.navigationBars["Content"].waitForExistence(timeout: 5))
        let youtubeSegment = app.segmentedControls.buttons["YouTube"]
        XCTAssertTrue(youtubeSegment.waitForExistence(timeout: 5))
        youtubeSegment.tap()

        // ツールバーの追加ボタンと、空状態の追加導線が出る
        XCTAssertTrue(app.buttons["youtubeAddButton"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No YouTube videos yet"].exists)
        XCTAssertTrue(app.buttons["Add YouTube"].exists)
        attach(app, "40-youtube-segment-empty")

        // レッスンが1つも無い状態では、追加シートは案内を出す（YouTube はレッスン必須）
        app.buttons["youtubeAddButton"].tap()
        XCTAssertTrue(app.staticTexts["No lessons yet"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["youtubeAddInput"].exists)
        attach(app, "41-youtube-add-no-lesson")
        app.navigationBars.buttons["Cancel"].tap()
    }

    func testAddYouTubeFromLibraryWithLessonPicker() throws {
        let app = XCUIApplication()
        // oEmbed のタイトル取得をスタブ化し、videoID → タイトル差し替えを決定的に検証する
        app.launchArguments += ["-uiTestStubYouTubeTitle", "Never Gonna Give You Up"]
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

        // YouTube セグメントの「+」で追加シートを開くと、レッスン選択（既定=最新）と入力欄が出る
        app.selectTab("Content")
        let youtubeSegment = app.segmentedControls.buttons["YouTube"]
        XCTAssertTrue(youtubeSegment.waitForExistence(timeout: 5))
        youtubeSegment.tap()
        XCTAssertTrue(app.buttons["youtubeAddButton"].waitForExistence(timeout: 5))
        app.buttons["youtubeAddButton"].tap()

        XCTAssertTrue(app.buttons["youtubeLessonPicker"].waitForExistence(timeout: 5))
        let input = app.textFields["youtubeAddInput"]
        XCTAssertTrue(input.exists)
        input.tap()
        input.typeText("dQw4w9WgXcQ")

        let confirm = app.buttons["youtubeAddConfirmButton"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        XCTAssertTrue(confirm.isEnabled)
        attach(app, "42-youtube-add-with-lesson-picker")
        confirm.tap()

        // シートが閉じ、一覧に取得タイトル + レッスン名サブタイトル付きで反映される
        XCTAssertTrue(input.waitForNonExistence(timeout: 5))
        let titleText = app.staticTexts["Never Gonna Give You Up"]
        XCTAssertTrue(titleText.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["ESL Beginner A / Unit 1 Greetings"].exists)
        attach(app, "43-youtube-library-row")

        // 行タップで YouTube 詳細へ遷移し、戻れば一覧に戻る
        titleText.tap()
        XCTAssertTrue(app.navigationBars["YouTube"].waitForExistence(timeout: 5))
        attach(app, "44-youtube-detail-from-library")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Content"].waitForExistence(timeout: 5))
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
