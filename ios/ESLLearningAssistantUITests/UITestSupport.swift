import XCTest

extension XCTestCase {
    /// Lessons タブの空状態からクラスを作成し、カレンダーの「Create Today's Lesson」で
    /// 今日のレッスンを1つ作成する（レッスン作成はカレンダー経由のみ。旧 LessonAddView は廃止）
    func createClassAndTodayLesson(
        _ app: XCUIApplication,
        className: String = "ESL Beginner A",
        lessonTitle: String = "Unit 1 Greetings"
    ) {
        let addClassButton = app.buttons["lessonAddClassButton"]
        XCTAssertTrue(addClassButton.waitForExistence(timeout: 5))
        addClassButton.tap()
        addClassInSwitcher(app, className: className)
        createTodayLessonInSwitcher(app, title: lessonTitle)
    }

    /// クラス未作成（空状態）の場合のみクラスと今日のレッスンを作成する。既存があれば何もしない
    func ensureClassAndTodayLesson(
        _ app: XCUIApplication,
        className: String = "ESL Beginner A",
        lessonTitle: String = "Unit 1 Greetings"
    ) {
        let addClassButton = app.buttons["lessonAddClassButton"]
        guard addClassButton.waitForExistence(timeout: 5) else { return }
        addClassButton.tap()
        addClassInSwitcher(app, className: className)
        createTodayLessonInSwitcher(app, title: lessonTitle)
    }

    /// 切り替えシートが開いている状態でクラスを追加する（追加後はシート内のカレンダーに戻る）
    func addClassInSwitcher(_ app: XCUIApplication, className: String) {
        let addButton = app.buttons["switcherAddClassButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap()
        let classNameField = app.textFields["classNameField"]
        XCTAssertTrue(classNameField.waitForExistence(timeout: 5))
        classNameField.tap()
        classNameField.typeText(className)
        app.navigationBars.buttons["Add"].tap()
    }

    /// 切り替えシートのカレンダーから今日のレッスンを作成する（作成・選択後シートは閉じる）。
    /// タイトルは作成確認アラートの任意入力欄に入れる（空文字なら未入力のまま作成）
    func createTodayLessonInSwitcher(_ app: XCUIApplication, title: String) {
        let todayButton = app.buttons["calendarTodayLessonButton"]
        XCTAssertTrue(todayButton.waitForExistence(timeout: 5))
        todayButton.tap()
        // SwiftUI アラート内 TextField は identifier が付かない場合があるため alerts 配下でも探す
        var titleField = app.textFields["lessonTitleField"]
        if !titleField.waitForExistence(timeout: 3) {
            titleField = app.alerts.textFields.firstMatch
            XCTAssertTrue(titleField.waitForExistence(timeout: 3))
        }
        if !title.isEmpty {
            titleField.tap()
            titleField.typeText(title)
        }
        app.buttons["Create"].tap()
    }
}

extension XCUIApplication {
    /// タブを名前で選ぶ。タブが 5 つ以上あると iPhone では 5 つ目以降が「More」タブに
    /// 押し込まれるため（本アプリは Lessons/Words/Writing/Audio/Documents/Settings の 6 タブ構成で
    /// Documents・Settings が overflow する）、タブバーに直接無ければ More 経由で選ぶ。
    func selectTab(_ name: String, timeout: TimeInterval = 8) {
        let direct = tabBars.buttons[name]
        if direct.waitForExistence(timeout: timeout) {
            direct.tap()
            return
        }
        let more = tabBars.buttons["More"]
        XCTAssertTrue(more.waitForExistence(timeout: timeout), "neither '\(name)' tab nor 'More' tab found")
        more.tap()
        // More は残りのタブ（Documents/Settings）をテーブルで一覧する。ただし一度 overflow タブを
        // 開いた後に More を再タップすると、一覧ではなく前回開いた画面が押し込まれたまま表示される。
        // その場合は「More」戻るボタンで一覧へ戻してから目的の行を選ぶ。描画遅延に備えて締切まで走査する。
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            for row in [tables.cells.staticTexts[name], tables.staticTexts[name]] where row.exists {
                row.tap()
                return
            }
            let back = navigationBars["More"].buttons["BackButton"]
            if back.exists {
                back.tap()
            }
            _ = tables.firstMatch.waitForExistence(timeout: 0.3)
        } while Date() < deadline
        XCTFail("'\(name)' not found in the More list")
    }
}
