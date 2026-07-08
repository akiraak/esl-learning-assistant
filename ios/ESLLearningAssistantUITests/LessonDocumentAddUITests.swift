import XCTest

/// ドキュメント取り込み（Phase 3/4）の導線を写真ライブラリ・システムのファイルピッカー非依存で検証する。
/// 実際の取り込みはシステムの Files ピッカー（`.fileImporter`）を経由し XCUITest から決定的に
/// 駆動できないため（音声取り込みに UI テストが無いのと同じ理由）、ここでは
/// (1) レッスンのコンテンツ追加シートに「Document」が並ぶこと、
/// (2) Documents タブが開けて取り込みの入口（＋ボタン・空状態）が出ること、
/// までを確認する。取り込み後の状態遷移は unit（DocumentExtractTranslateServiceTests 等）で担保。
final class LessonDocumentAddUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testDocumentTypeAppearsInLessonContentPicker() throws {
        let app = XCUIApplication()
        app.launch()

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

        // 4タイプ（写真 / Audio / Document / YouTube）が並び、Document 行が選択可能
        XCTAssertTrue(app.buttons["addContentPhotoButton"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["addContentAudioButton"].exists)
        let documentTypeButton = app.buttons["addContentDocumentButton"]
        XCTAssertTrue(documentTypeButton.exists)
        XCTAssertTrue(documentTypeButton.isEnabled)
        XCTAssertTrue(app.buttons["addContentYouTubeButton"].exists)
        XCTAssertTrue(app.staticTexts["Import a PDF or Word file"].exists)
        attach(app, "30-add-content-type-picker-with-document")
    }

    func testDocumentsTabShowsImportEntryPoints() throws {
        let app = XCUIApplication()
        app.launch()

        clearAllData(app)

        // Documents タブは 5 つ目以降のため「More」に入る。selectTab が overflow を吸収する。
        app.selectTab("Documents")

        XCTAssertTrue(app.navigationBars["Documents"].waitForExistence(timeout: 5))
        // ツールバーの取り込みボタンと、空状態の取り込み導線が出る
        XCTAssertTrue(app.buttons["documentImportButton"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No documents yet"].exists)
        XCTAssertTrue(app.buttons["Import Document"].exists)
        attach(app, "31-documents-tab-empty")
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
