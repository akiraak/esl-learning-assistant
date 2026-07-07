import XCTest

final class ReviewSessionUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// サーバに到達できないときの挙動: 「今日の復習」カードから開始すると
    /// 取得失敗画面（Retry 付き）になり、reviewState は変化しない（カードの件数が減らない）。
    /// 問題はサーバ保存のもののみを使うため、オフラインでは出題されないのが仕様。
    func testReviewShowsLoadFailureWhenServerUnreachable() throws {
        let app = XCUIApplication()
        // 到達不能なURLを UserDefaults の引数ドメインへ注入して確実に取得失敗させる
        app.launchArguments += ["-backendBaseURL", "http://127.0.0.1:1", "-uiTestStubWordNormalize", "canonical"]
        app.launch()

        clearAllData(app)

        app.tabBars.buttons["Words"].tap()
        for word in ["apple", "banana"] {
            addWord(app, text: word)
        }

        let startButton = app.buttons["reviewStartButton"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["2 words to review"].exists)
        startButton.tap()

        // 取得失敗画面（Retry あり）。出題も reviewState 更新もされない
        let retryButton = app.buttons["reviewRetryLoadButton"]
        XCTAssertTrue(retryButton.waitForExistence(timeout: 10))
        attach(app, "01-load-failed")

        app.buttons["reviewCloseButton"].tap()
        XCTAssertTrue(app.staticTexts["2 words to review"].waitForExistence(timeout: 5))
        attach(app, "02-card-unchanged")
    }

    /// サーバ問題での通し確認（要ローカルサーバ）。既定ではスキップされる。
    /// 実行方法:
    ///   TEST_RUNNER_REVIEW_E2E_BASE_URL=http://127.0.0.1:8899 \
    ///   TEST_RUNNER_REVIEW_E2E_API_SECRET=<backend/.env の API_SECRET> \
    ///   xcodebuild test ... -only-testing:ESLLearningAssistantUITests/ReviewSessionUITests/testTodayReviewFlowWithServerQuestions
    /// 単語情報→問題の生成に時間がかかるため、「Preparing Questions」なら待って再入場する。
    func testTodayReviewFlowWithServerQuestions() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let baseURL = environment["REVIEW_E2E_BASE_URL"],
              let apiSecret = environment["REVIEW_E2E_API_SECRET"] else {
            throw XCTSkip("REVIEW_E2E_BASE_URL / REVIEW_E2E_API_SECRET 未設定のためスキップ")
        }

        let app = XCUIApplication()
        app.launchArguments += [
            "-backendBaseURL", baseURL,
            "-apiSecret", apiSecret,
            "-uiTestStubWordNormalize", "canonical",
        ]
        app.launch()

        clearAllData(app)

        // 単語登録 → AI情報生成の成功後に問題生成がサーバへトリガされる
        app.tabBars.buttons["Words"].tap()
        for word in ["apple", "banana"] {
            addWord(app, text: word)
        }

        let startButton = app.buttons["reviewStartButton"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 5))
        attach(app, "01-today-review-card")

        // 問題生成が終わるまで「Preparing Questions」→ 閉じて待つ、を繰り返して入場する
        let doneButton = app.buttons["reviewDoneButton"]
        var entered = false
        for _ in 0..<12 {
            startButton.tap()
            if app.buttons["reviewChoiceButton0"].waitForExistence(timeout: 15)
                || app.textFields["reviewTypedAnswerField"].exists {
                entered = true
                break
            }
            // 未生成（Preparing Questions）または全スキップ → 閉じて生成完了を待つ
            XCTAssertTrue(doneButton.waitForExistence(timeout: 10), "出題も準備中表示も出ない")
            attach(app, "02-preparing")
            doneButton.tap()
            XCTAssertTrue(startButton.waitForExistence(timeout: 5))
            Thread.sleep(forTimeInterval: 10)
        }
        XCTAssertTrue(entered, "問題生成が完了せず出題に到達できない")
        attach(app, "03-first-question")

        // サマリーまで 出題→回答→次へ を繰り返す（形式はランダムのため分岐して回答）
        var screenshotTaken = false
        for turn in 0..<20 {
            if doneButton.waitForExistence(timeout: 3) {
                break
            }
            let choiceButton = app.buttons["reviewChoiceButton0"]
            let answerField = app.textFields["reviewTypedAnswerField"]
            if choiceButton.waitForExistence(timeout: 5) {
                choiceButton.tap()
            } else if answerField.waitForExistence(timeout: 2) {
                answerField.tap()
                answerField.typeText("apple")
                let submitButton = app.buttons["reviewSubmitButton"]
                XCTAssertTrue(submitButton.waitForExistence(timeout: 3))
                submitButton.tap()
            } else {
                XCTFail("出題画面に回答UIが見つからない (turn \(turn))")
            }

            let nextButton = app.buttons["reviewNextButton"]
            XCTAssertTrue(nextButton.waitForExistence(timeout: 5), "フィードバックが表示されない (turn \(turn))")
            if !screenshotTaken {
                attach(app, "04-feedback")
                screenshotTaken = true
            }
            nextButton.tap()
        }

        XCTAssertTrue(doneButton.waitForExistence(timeout: 5), "サマリーが表示されない")
        XCTAssertTrue(app.staticTexts["Session Complete"].exists)
        attach(app, "05-session-summary")
        doneButton.tap()

        // 習熟度方式では正誤に応じて未クリアの単語が due に残ることがあるため、
        // 完了表示（全単語クリア）か再開カード（未クリアあり）のどちらかに戻ればよい
        let completeLabel = app.staticTexts["reviewCompleteLabel"]
        XCTAssertTrue(
            completeLabel.waitForExistence(timeout: 5)
                || app.buttons["reviewStartButton"].waitForExistence(timeout: 5)
        )
        attach(app, "06-review-card-after-session")
    }

    /// WordDetailView の Review セクション: 新規登録語は「Due today」・Step 1/5・Reviews 0 を表示する
    /// （Phase 4: docs/plans/archive/word-memorization-quiz.md §3.5）
    func testWordDetailShowsReviewStatus() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-backendBaseURL", "http://127.0.0.1:1", "-uiTestStubWordNormalize", "canonical"]
        app.launch()

        clearAllData(app)
        app.tabBars.buttons["Words"].tap()
        addWord(app, text: "apple")

        app.staticTexts["apple"].tap()

        // Review セクションは画面下部にあり List の遅延生成で最初は存在しないため、見えるまでスクロールする。
        // LabeledContent はラベルと値が1つのアクセシビリティ要素に結合されるため identifier で参照する
        let nextRow = app.staticTexts["wordReviewNextRow"]
        for _ in 0..<6 where !nextRow.exists {
            app.swipeUp()
        }
        XCTAssertTrue(nextRow.waitForExistence(timeout: 5), "Next Review 行が見つからない")
        XCTAssertTrue(nextRow.label.contains("Due today"), "新規登録語は当日が復習日: \(nextRow.label)")
        let stepRow = app.staticTexts["wordReviewStepRow"]
        XCTAssertTrue(stepRow.exists)
        XCTAssertTrue(stepRow.label.contains("1 / 5 (+3 days)"), "Step 表示: \(stepRow.label)")
        attach(app, "word-detail-review-status")
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
