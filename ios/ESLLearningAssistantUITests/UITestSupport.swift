import XCTest

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
