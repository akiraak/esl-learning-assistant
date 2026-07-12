import XCTest

final class ESLLearningAssistantUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testTabsAreVisible() throws {
        let app = XCUIApplication()
        app.launch()

        // 5 タブ構成（6 個以上だと iOS の「More」タブに入り、ナビゲーションバーが二重になるため）。
        // 全タブが直接見えること・More が存在しないことを確認する。
        XCTAssertTrue(app.tabBars.buttons["Lessons"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Words"].exists)
        XCTAssertTrue(app.tabBars.buttons["Writing"].exists)
        XCTAssertTrue(app.tabBars.buttons["Content"].exists)
        XCTAssertTrue(app.tabBars.buttons["Settings"].exists)
        XCTAssertFalse(app.tabBars.buttons["More"].exists)
        app.selectTab("Settings")
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
        addClassInSwitcher(app, className: "ESL Beginner A")
        attach(app, "02-switcher-class-added")

        createTodayLessonInSwitcher(app, title: "Unit 1 Greetings")
        attach(app, "04-lesson-with-lesson")

        let addContentButton = app.buttons["lessonContentAddButton"]
        XCTAssertTrue(addContentButton.waitForExistence(timeout: 5))
        addContentButton.tap()
        attach(app, "05-add-content-type")

        // タイプ選択シートで「Photo」を選ぶと写真取り込みへ進む
        let choosePhotoTypeButton = app.buttons["addContentPhotoButton"]
        XCTAssertTrue(choosePhotoTypeButton.waitForExistence(timeout: 5))
        choosePhotoTypeButton.tap()
        attach(app, "05b-capture-sheet")

        // CaptureView のライブラリ選択ボタンは複数選択対応で "Choose Photos"（2026-07-05 の複数取り込み対応）
        let pickPhotoButton = app.buttons["Choose Photos"]
        XCTAssertTrue(pickPhotoButton.waitForExistence(timeout: 5))
        pickPhotoButton.tap()

        // PHPicker はプロセス外ホストだが、iOS 26 からは写真グリッドのセルが
        // identifier "PXGGridLayout-Info" の Image 要素としてクエリできる
        // （座標タップはプライバシー告知バナーの高さ変動でグリッド位置がずれ、空振りする）
        let photoCell = app.images.matching(identifier: "PXGGridLayout-Info").element(boundBy: 2)
        XCTAssertTrue(photoCell.waitForExistence(timeout: 10))
        attach(app, "06-photos-picker")
        // リモート要素は hit point が計算できず element.tap() が Not hittable になるため、
        // 要素 frame の中心を座標タップする
        photoCell.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        attach(app, "06b-picker-after-select")
        confirmPhotoPickerSelection(app)

        // 現行フローは追加後に詳細へ自動遷移せず、レッスン画面のコンテンツ一覧に写真行が載る
        // （OCR/翻訳はバックグラウンド実行）。行をタップして写真詳細を開く
        let photoRow = app.buttons["lessonPhotoRow"].firstMatch
        XCTAssertTrue(photoRow.waitForExistence(timeout: 10))
        attach(app, "07-lesson-content-with-photo")
        photoRow.tap()

        // OCR・翻訳は実バックエンド呼び出しのため完了までのタイムアウトは長めに取る
        let ocrHeading = app.staticTexts["OCR Result (English)"]
        XCTAssertTrue(ocrHeading.waitForExistence(timeout: 90))
        attach(app, "08-photo-detail")
    }

    /// PHPicker の選択確定。iOS 26 では確定がナビバーの「追加/Add」ではなく右上の ✓ ボタン
    /// （identifier 無し、label はロケール依存で 完了/Done）に変わった。✓ は写真を選択するまで
    /// Disabled のため、「既知ラベルかつ enabled」のボタンが現れるのを待ってタップする。
    /// 現れない場合はセル選択が効いていないので、調査用に accessibility ツリーを添付して失敗させる
    private func confirmPhotoPickerSelection(_ app: XCUIApplication) {
        let confirmButton = app.buttons.matching(
            NSPredicate(format: "label IN %@ AND enabled == YES", ["完了", "Done", "追加", "Add"])
        ).firstMatch
        guard confirmButton.waitForExistence(timeout: 10) else {
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "photo-picker-accessibility-tree"
            tree.lifetime = .keepAlways
            add(tree)
            XCTFail("PHPicker の確定ボタン（完了/Done）が有効にならない（写真選択が登録されていない）")
            return
        }
        // リモート要素の hit point 計算失敗（Not hittable）を避け、frame 中心を座標タップする
        confirmButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    func testSameDayLessonOpensExistingInsteadOfCreating() throws {
        let app = XCUIApplication()
        app.launch()

        // クラス・今日のレッスンを用意する（未作成の場合のみ）
        ensureClassAndTodayLesson(app)

        // 切り替えシートを開き、もう一度「今日」をタップする。クラス内で同日は1レッスンなので
        // 作成アラートは出ず、既存の今日のレッスンが選択されてシートが閉じる
        let switcherButton = app.buttons["classLessonSwitcherButton"]
        XCTAssertTrue(switcherButton.waitForExistence(timeout: 5))
        switcherButton.tap()

        let todayButton = app.buttons["calendarTodayLessonButton"]
        XCTAssertTrue(todayButton.waitForExistence(timeout: 5))
        XCTAssertTrue(todayButton.label.contains("Open Today's Lesson"))
        attach(app, "17-calendar-open-today")
        todayButton.tap()

        // 作成アラートは表示されず、シートが閉じてレッスン画面に戻る
        XCTAssertFalse(app.alerts.firstMatch.waitForExistence(timeout: 2))
        XCTAssertTrue(switcherButton.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Unit 1 Greetings"].waitForExistence(timeout: 5))
        attach(app, "18-same-day-lesson-selected")
    }

    func testWordAddFlow() throws {
        let app = XCUIApplication()
        app.launch()

        // クラス・レッスンを用意する（未作成の場合のみ）
        ensureClassAndTodayLesson(app)

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

        // レッスンの単語タップ → レッスン画面のまま詳細が表示され、戻るとレッスンに戻る
        app.staticTexts["apple"].tap()
        XCTAssertTrue(app.navigationBars["apple"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Lessons"].isSelected)
        attach(app, "15-word-detail-via-lesson-tap")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["apple"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Lessons"].isSelected)

        // 単語タブ: 検索で絞り込める
        app.tabBars.buttons["Words"].tap()
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
        app.selectTab("Settings")
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
        app.selectTab("Settings")
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
        app.selectTab("Settings")
        let clearButton = app.buttons["Delete All Data"]
        XCTAssertTrue(clearButton.waitForExistence(timeout: 5))
        app.swipeUp()
        clearButton.tap()
        let deleteButton = app.buttons["Delete"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 5))
        deleteButton.tap()

        app.tabBars.buttons["Lessons"].tap()
        let addClassButton = app.buttons["lessonAddClassButton"]
        createClassAndTodayLesson(app, className: "Debug Class", lessonTitle: "Unit 1")

        // クラス指定で削除する
        app.selectTab("Settings")
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

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
