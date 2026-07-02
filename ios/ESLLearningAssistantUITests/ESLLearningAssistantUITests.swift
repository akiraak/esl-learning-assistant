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

        // 前回実行のデータが残っていると空状態から始められないため、先に全クリアする
        clearAllData(app)
        app.tabBars.buttons["Lessons"].tap()
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
        app.navigationBars.buttons["Add"].tap()
        attach(app, "02-switcher-class-added")

        let addLessonButton = app.buttons["switcherAddLessonButton"]
        XCTAssertTrue(addLessonButton.waitForExistence(timeout: 5))
        addLessonButton.tap()

        let lessonTitleField = app.textFields["lessonTitleField"]
        XCTAssertTrue(lessonTitleField.waitForExistence(timeout: 5))
        lessonTitleField.tap()
        lessonTitleField.typeText("Unit 1 Greetings")
        app.navigationBars.buttons["Add"].tap()
        attach(app, "04-lesson-with-lesson")

        let capturePhotoButton = app.buttons["lessonPhotoAddButton"]
        XCTAssertTrue(capturePhotoButton.waitForExistence(timeout: 5))
        capturePhotoButton.tap()
        attach(app, "05-capture-sheet")

        let pickPhotoButton = app.buttons["Choose Photo"]
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

        // PHPickerはOS側UIのため、シミュレータのロケール依存のボタン（日本語/英語）を両方許容する
        if app.navigationBars.buttons["追加"].waitForExistence(timeout: 3) {
            app.navigationBars.buttons["追加"].tap()
        } else if app.navigationBars.buttons["Add"].waitForExistence(timeout: 1) {
            app.navigationBars.buttons["Add"].tap()
        }

        let ocrHeading = app.staticTexts["OCR Result (English)"]
        XCTAssertTrue(ocrHeading.waitForExistence(timeout: 10))
        attach(app, "07-photo-detail")
    }

    func testDuplicateLessonTitleBlocked() throws {
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
            app.navigationBars.buttons["Add"].tap()
            let addLessonButton = app.buttons["switcherAddLessonButton"]
            XCTAssertTrue(addLessonButton.waitForExistence(timeout: 5))
            addLessonButton.tap()
            let lessonTitleField = app.textFields["lessonTitleField"]
            XCTAssertTrue(lessonTitleField.waitForExistence(timeout: 5))
            lessonTitleField.tap()
            lessonTitleField.typeText("Unit 1 Greetings")
            app.navigationBars.buttons["Add"].tap()
        }

        // 切り替えシートを開き、既存と同名のレッスンを追加しようとする
        let switcherButton = app.buttons["classLessonSwitcherButton"]
        XCTAssertTrue(switcherButton.waitForExistence(timeout: 5))
        switcherButton.tap()
        let addLessonButton = app.buttons["switcherAddLessonButton"].firstMatch
        XCTAssertTrue(addLessonButton.waitForExistence(timeout: 5))
        addLessonButton.tap()

        let lessonTitleField = app.textFields["lessonTitleField"]
        XCTAssertTrue(lessonTitleField.waitForExistence(timeout: 5))
        lessonTitleField.tap()
        lessonTitleField.typeText("Unit 1 Greetings")

        // 追加ボタンが無効になり、重複メッセージが表示される
        let addButton = app.navigationBars.buttons["Add"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        XCTAssertFalse(addButton.isEnabled)
        XCTAssertTrue(
            app.staticTexts["ESL Beginner A already has a lesson with this name."]
                .waitForExistence(timeout: 5)
        )
        attach(app, "17-duplicate-lesson-blocked")

        // 別名にすれば追加できる
        lessonTitleField.typeText(" 2")
        XCTAssertTrue(addButton.isEnabled)
        attach(app, "18-unique-lesson-allowed")
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
            app.navigationBars.buttons["Add"].tap()
            let addLessonButton = app.buttons["switcherAddLessonButton"]
            XCTAssertTrue(addLessonButton.waitForExistence(timeout: 5))
            addLessonButton.tap()
            let lessonTitleField = app.textFields["lessonTitleField"]
            XCTAssertTrue(lessonTitleField.waitForExistence(timeout: 5))
            lessonTitleField.tap()
            lessonTitleField.typeText("Unit 1 Greetings")
            app.navigationBars.buttons["Add"].tap()
        }

        // 単語タブ: レッスン指定ありで追加（入力は見出し語のみ）
        app.tabBars.buttons["Words"].tap()
        attach(app, "10-words-tab")

        app.buttons["wordAddButton"].tap()
        let textField = app.textFields["wordTextField"]
        XCTAssertTrue(textField.waitForExistence(timeout: 5))
        textField.tap()
        textField.typeText("apple")

        app.buttons["wordLessonPicker"].tap()
        let lessonOption = app.buttons["ESL Beginner A / Unit 1 Greetings"]
        XCTAssertTrue(lessonOption.waitForExistence(timeout: 5))
        lessonOption.tap()
        attach(app, "11-word-add-form-with-lesson")
        app.navigationBars.buttons["Add"].tap()

        XCTAssertTrue(app.staticTexts["apple"].waitForExistence(timeout: 5))
        attach(app, "12-words-list")

        // 単語タブ: レッスン指定なしでも追加できる
        app.buttons["wordAddButton"].tap()
        XCTAssertTrue(textField.waitForExistence(timeout: 5))
        textField.tap()
        textField.typeText("book")
        app.navigationBars.buttons["Add"].tap()
        XCTAssertTrue(app.staticTexts["book"].waitForExistence(timeout: 5))

        // 単語詳細: 登場レッスンが表示される
        // （AI単語情報セクションが上に入るため、必要ならスクロールして探す）
        app.staticTexts["apple"].tap()
        XCTAssertTrue(app.navigationBars["apple"].waitForExistence(timeout: 5))
        scrollTo(app, staticText: "Unit 1 Greetings")
        XCTAssertTrue(app.staticTexts["Unit 1 Greetings"].exists)
        attach(app, "13-word-detail")
        app.navigationBars.buttons.firstMatch.tap()

        // レッスンタブ: 単語セクションに反映される
        app.tabBars.buttons["Lessons"].tap()
        XCTAssertTrue(app.staticTexts["apple"].waitForExistence(timeout: 5))
        attach(app, "14-lesson-with-word")

        // レッスンの単語タップ → Wordsタブに切り替わり詳細が表示される
        app.staticTexts["apple"].tap()
        XCTAssertTrue(app.navigationBars["apple"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Words"].isSelected)
        attach(app, "15-word-detail-via-lesson-tap")
        app.navigationBars.buttons.firstMatch.tap()

        // 単語タブ: 検索で絞り込める
        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        searchField.typeText("app")
        XCTAssertTrue(app.staticTexts["apple"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["book"].exists)
        attach(app, "16-words-search")
    }

    func testDebugMenuClearAllData() throws {
        let app = XCUIApplication()
        app.launch()

        // 消える対象の単語を1件用意する（レッスン指定なしで追加できる）
        app.tabBars.buttons["Words"].tap()
        app.buttons["wordAddButton"].tap()
        let textField = app.textFields["wordTextField"]
        XCTAssertTrue(textField.waitForExistence(timeout: 5))
        textField.tap()
        textField.typeText("zebra")
        app.navigationBars.buttons["Add"].tap()
        XCTAssertTrue(app.staticTexts["zebra"].waitForExistence(timeout: 5))

        // 設定タブのデバッグメニューを開く（フローティングタブバーに隠れるためスクロールする）
        app.tabBars.buttons["Settings"].tap()
        let clearButton = app.buttons["Delete All Data"]
        XCTAssertTrue(clearButton.waitForExistence(timeout: 5))
        app.swipeUp()
        attach(app, "19-settings-debug-section")

        // ダイアログを閉じただけでは削除されない
        // （iOS 26のconfirmationDialogはポップオーバー表示でキャンセルボタンが出ないため、
        //   外側タップで閉じる）
        clearButton.tap()
        let deleteButton = app.buttons["Delete"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 5))
        attach(app, "20-debug-clear-confirmation")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55)).tap()
        XCTAssertTrue(deleteButton.waitForNonExistence(timeout: 5))
        app.tabBars.buttons["Words"].tap()
        XCTAssertTrue(app.staticTexts["zebra"].waitForExistence(timeout: 5))

        // 削除を実行すると単語が消える
        app.tabBars.buttons["Settings"].tap()
        app.swipeUp()
        clearButton.tap()
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 5))
        deleteButton.tap()

        app.tabBars.buttons["Words"].tap()
        XCTAssertTrue(app.staticTexts["zebra"].waitForNonExistence(timeout: 5))
        attach(app, "21-words-after-clear")
    }

    func testDebugMenuDeleteSpecificClass() throws {
        let app = XCUIApplication()
        app.launch()

        // 状態を確定させるため、まず全クリアしてからクラス・レッスンを1組作る
        app.tabBars.buttons["Settings"].tap()
        let clearButton = app.buttons["Delete All Data"]
        XCTAssertTrue(clearButton.waitForExistence(timeout: 5))
        app.swipeUp()
        clearButton.tap()
        let deleteButton = app.buttons["Delete"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 5))
        deleteButton.tap()

        app.tabBars.buttons["Lessons"].tap()
        let addClassButton = app.buttons["lessonAddClassButton"]
        XCTAssertTrue(addClassButton.waitForExistence(timeout: 5))
        addClassButton.tap()
        app.buttons["switcherAddClassButton"].tap()
        let classNameField = app.textFields["classNameField"]
        XCTAssertTrue(classNameField.waitForExistence(timeout: 5))
        classNameField.tap()
        classNameField.typeText("Debug Class")
        app.navigationBars.buttons["Add"].tap()
        let addLessonButton = app.buttons["switcherAddLessonButton"]
        XCTAssertTrue(addLessonButton.waitForExistence(timeout: 5))
        addLessonButton.tap()
        let lessonTitleField = app.textFields["lessonTitleField"]
        XCTAssertTrue(lessonTitleField.waitForExistence(timeout: 5))
        lessonTitleField.tap()
        lessonTitleField.typeText("Unit 1")
        app.navigationBars.buttons["Add"].tap()

        // クラス指定で削除する
        app.tabBars.buttons["Settings"].tap()
        let deleteClassButton = app.buttons["Delete a Class and Its Lessons"]
        XCTAssertTrue(deleteClassButton.waitForExistence(timeout: 5))
        app.swipeUp()
        deleteClassButton.tap()
        let classOption = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Debug Class")
        ).firstMatch
        XCTAssertTrue(classOption.waitForExistence(timeout: 5))
        attach(app, "22-debug-delete-class-dialog")
        classOption.tap()

        // レッスンタブが空状態（クラス作成ボタン表示）に戻る
        app.tabBars.buttons["Lessons"].tap()
        XCTAssertTrue(addClassButton.waitForExistence(timeout: 5))
        attach(app, "23-lessons-after-class-delete")
    }

    func testWordAIInfoStatusUI() throws {
        // 到達不能なバックエンドURLを指定して生成を確実に失敗させ、
        // ネットワーク非依存で詳細画面の生成ステータスUIを確認する
        let app = XCUIApplication()
        app.launchArguments += ["-backendBaseURL", "http://127.0.0.1:9"]
        app.launch()

        app.tabBars.buttons["Words"].tap()
        app.buttons["wordAddButton"].tap()
        let textField = app.textFields["wordTextField"]
        XCTAssertTrue(textField.waitForExistence(timeout: 5))
        textField.tap()
        textField.typeText("melon")
        app.navigationBars.buttons["Add"].tap()

        // 登録で自動生成が始まり、接続失敗で failed になる
        XCTAssertTrue(app.staticTexts["melon"].waitForExistence(timeout: 5))
        app.staticTexts["melon"].tap()
        XCTAssertTrue(app.staticTexts["Generation failed"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["wordAIInfoRetryButton"].exists)
        attach(app, "24-word-ai-info-failed")

        // 再試行しても失敗のまま（到達不能URL）だが、ボタンが機能しクラッシュしないこと
        app.buttons["wordAIInfoRetryButton"].tap()
        XCTAssertTrue(app.staticTexts["Generation failed"].waitForExistence(timeout: 10))
    }

    /// 設定タブのデバッグメニューからデータを全クリアする
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

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
