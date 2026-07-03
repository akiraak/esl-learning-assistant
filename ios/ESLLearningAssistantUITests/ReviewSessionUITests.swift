import XCTest

final class ReviewSessionUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Words タブの「今日の復習」カード → ReviewSessionView の出題 → 回答 →
    /// フィードバック → サマリー → 完了表示、の一連の導線を通す。
    /// 出題形式は比率調整付きのランダム選定のため、4択・タイプ入力のどちらが来ても
    /// 進められるように分岐して回答する（正誤は問わない）。
    func testTodayReviewFlowFromWordsTab() throws {
        let app = XCUIApplication()
        app.launch()

        clearAllData(app)

        // 単語を4件登録する（4択の誤答選択肢が組める最小構成）
        app.tabBars.buttons["Words"].tap()
        for word in ["apple", "banana", "orange", "grape"] {
            addWord(app, text: word)
        }

        // 新規登録語は当日から復習対象 → カードに件数が出る
        let startButton = app.buttons["reviewStartButton"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["4 words to review"].exists)
        attach(app, "01-today-review-card")

        startButton.tap()

        // セッション: サマリーが出るまで出題→回答→次へ を繰り返す
        // （初回不正解の単語は最後に再出題されるため最大8問 + 余裕）
        let doneButton = app.buttons["reviewDoneButton"]
        var screenshotTaken = false
        for turn in 0..<20 {
            if doneButton.waitForExistence(timeout: 3) {
                break
            }

            let choiceButton = app.buttons["reviewChoiceButton0"]
            let answerField = app.textFields["reviewTypedAnswerField"]
            if choiceButton.waitForExistence(timeout: 5) {
                if !screenshotTaken {
                    attach(app, "02-question-choices")
                    screenshotTaken = true
                }
                choiceButton.tap()
            } else if answerField.waitForExistence(timeout: 2) {
                attach(app, "02b-question-typing")
                answerField.tap()
                answerField.typeText("apple")
                let submitButton = app.buttons["reviewSubmitButton"]
                XCTAssertTrue(submitButton.waitForExistence(timeout: 3))
                submitButton.tap()
            } else {
                XCTFail("出題画面に回答UIが見つからない (turn \(turn))")
            }

            // 正誤フィードバックが表示され、Next で次の問題へ進む
            let nextButton = app.buttons["reviewNextButton"]
            XCTAssertTrue(nextButton.waitForExistence(timeout: 5), "フィードバックが表示されない (turn \(turn))")
            XCTAssertTrue(
                app.staticTexts["Correct!"].exists || app.staticTexts["Incorrect"].exists,
                "正誤表示が見つからない (turn \(turn))"
            )
            if turn == 0 {
                attach(app, "03-feedback")
            }
            nextButton.tap()
        }

        // サマリー表示 → Done でセッションを閉じる
        XCTAssertTrue(doneButton.waitForExistence(timeout: 5), "サマリーが表示されない")
        XCTAssertTrue(app.staticTexts["Session Complete"].exists)
        attach(app, "04-session-summary")
        doneButton.tap()

        // 全単語が解答済み（正解は+3日以降、不正解も+3日）→ 今日の復習は完了表示
        let completeLabel = app.staticTexts["reviewCompleteLabel"]
        XCTAssertTrue(completeLabel.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["reviewStartButton"].exists)
        attach(app, "05-review-complete-card")
    }

    /// Words タブの通常追加シートで単語を1件登録する
    private func addWord(_ app: XCUIApplication, text: String) {
        app.buttons["wordAddButton"].tap()
        let wordTextField = app.textFields["wordTextField"]
        XCTAssertTrue(wordTextField.waitForExistence(timeout: 5))
        wordTextField.tap()
        wordTextField.typeText(text)
        app.navigationBars.buttons["Add"].tap()
        XCTAssertTrue(wordTextField.waitForNonExistence(timeout: 5))
    }

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

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
