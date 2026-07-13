import XCTest

/// Lesson のコンテンツ追加シートで Audio / Document をタップしたとき、
/// システムの Files ピッカー（`.fileImporter`）が実際に提示されることを検証する。
///
/// 背景: 同一 View に `.fileImporter` を2つチェーンしていたため後勝ちで
/// Document 側のみ有効になり、Audio をタップしても何も出ない不具合があった。
/// 現在は単一の fileImporter を種別 state で切り替えて共用している。
/// ピッカー内のファイル選択まではリモートビューのため決定的に駆動できず、ここでは
/// 「タップでピッカーが提示されること」までを確認する（取り込み処理は unit で担保）。
final class LessonAudioAddUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testAudioTypePresentsFilePicker() throws {
        let app = XCUIApplication()
        app.launch()

        clearAllData(app)
        app.tabBars.buttons["Lessons"].tap()
        createClassAndTodayLesson(app)

        openAddContentSheet(app)
        let audioButton = app.buttons["addContentAudioButton"]
        XCTAssertTrue(audioButton.waitForExistence(timeout: 5))
        audioButton.tap()

        XCTAssertTrue(
            waitForFilePicker(app),
            "Files picker did not appear after tapping Audio"
        )
        attach(app, "32-audio-file-picker-presented")
    }

    /// fileImporter 統合後も Document 側が従来どおり提示されるリグレッション確認
    func testDocumentTypePresentsFilePicker() throws {
        let app = XCUIApplication()
        app.launch()

        clearAllData(app)
        app.tabBars.buttons["Lessons"].tap()
        createClassAndTodayLesson(app)

        openAddContentSheet(app)
        let documentButton = app.buttons["addContentDocumentButton"]
        XCTAssertTrue(documentButton.waitForExistence(timeout: 5))
        documentButton.tap()

        XCTAssertTrue(
            waitForFilePicker(app),
            "Files picker did not appear after tapping Document"
        )
        attach(app, "33-document-file-picker-presented")
    }

    private func openAddContentSheet(_ app: XCUIApplication) {
        let addContentButton = app.buttons["lessonContentAddButton"]
        XCTAssertTrue(addContentButton.waitForExistence(timeout: 5))
        addContentButton.tap()
    }

    /// Files ピッカー（リモートビュー）の出現を待つ。Add Content シート側には存在しない
    /// ピッカー特有の要素（検索フィールド / Recents / Browse）のいずれかで検出する。
    private func waitForFilePicker(_ app: XCUIApplication, timeout: TimeInterval = 10) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if app.searchFields.firstMatch.exists { return true }
            if app.navigationBars["Recents"].exists { return true }
            if app.staticTexts["Recents"].exists { return true }
            if app.buttons["Browse"].exists { return true }
            _ = app.otherElements.firstMatch.waitForExistence(timeout: 0.5)
        } while Date() < deadline
        return false
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
