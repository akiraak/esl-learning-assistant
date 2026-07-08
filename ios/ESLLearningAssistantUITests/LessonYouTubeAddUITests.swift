import XCTest

/// レッスンコンテンツの複数タイプ対応（Phase 3/4）の E2E 確認。
/// 「＋」→ タイプ選択シート → YouTube 追加 → 統合コンテンツ一覧に反映、までを写真ライブラリ非依存で検証する。
final class LessonYouTubeAddUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testAddYouTubeFromContentTypePicker() throws {
        let app = XCUIApplication()
        // oEmbed のタイトル取得をスタブ化し、videoID → タイトル差し替えを決定的に検証する
        app.launchArguments += ["-uiTestStubYouTubeTitle", "Never Gonna Give You Up"]
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

        // Content セクションの「＋」でタイプ選択シートを開く
        let addContentButton = app.buttons["lessonContentAddButton"]
        XCTAssertTrue(addContentButton.waitForExistence(timeout: 5))
        addContentButton.tap()

        // 3タイプ（写真 / Audio / YouTube）が並ぶ
        XCTAssertTrue(app.buttons["addContentPhotoButton"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["addContentAudioButton"].exists)
        let youtubeTypeButton = app.buttons["addContentYouTubeButton"]
        XCTAssertTrue(youtubeTypeButton.exists)
        attach(app, "20-add-content-type-picker")

        // YouTube を選び、動画ID を入力して追加する
        youtubeTypeButton.tap()
        let input = app.textFields["youtubeAddInput"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText("dQw4w9WgXcQ")

        let confirm = app.buttons["youtubeAddConfirmButton"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        XCTAssertTrue(confirm.isEnabled)
        attach(app, "21-youtube-add-preview")
        confirm.tap()

        // フロー全体（シート）が閉じてレッスン画面へ戻り、統合コンテンツ一覧に反映される
        XCTAssertTrue(input.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Lessons"].isSelected)
        XCTAssertTrue(app.staticTexts["Content (1)"].waitForExistence(timeout: 5))

        // oEmbed バックフィルにより、行表示が videoID から取得タイトルへ差し替わる
        let titleText = app.staticTexts["Never Gonna Give You Up"]
        XCTAssertTrue(titleText.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["dQw4w9WgXcQ"].exists)
        attach(app, "22-youtube-in-content-list")

        // 行タップで YouTube 詳細へ遷移できる
        titleText.tap()
        XCTAssertTrue(app.navigationBars["YouTube"].waitForExistence(timeout: 5))
        attach(app, "23-youtube-detail")
    }

    func testYouTubeAddButtonDisabledForInvalidInput() throws {
        let app = XCUIApplication()
        app.launch()
        clearAllData(app)
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

        app.buttons["lessonContentAddButton"].tap()
        app.buttons["addContentYouTubeButton"].tap()

        let input = app.textFields["youtubeAddInput"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText("not a valid id")

        // 抽出不可の入力では Add が無効で、エラーメッセージが出る
        let confirm = app.buttons["youtubeAddConfirmButton"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        XCTAssertFalse(confirm.isEnabled)
        XCTAssertTrue(app.staticTexts["Invalid YouTube video ID or URL"].exists)
        attach(app, "24-youtube-invalid-input")
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
