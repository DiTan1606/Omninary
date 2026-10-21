import XCTest

/// Runs one real vocabulary session against the signed-in account on this
/// simulator. It writes real progress, so it only runs when explicitly selected
/// (`-only-testing:OmninaryUITests/RealLearningSessionUITests`).
final class RealLearningSessionUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCompleteOneRealSession() throws {
        try runSession(extraTheme: false, struggleWords: 0)
    }

    /// Extra: struggle on two words (give up first, right on retry) to see
    /// hold decisions next to jumps for the words answered well.
    @MainActor
    func testExtraSessionWithStruggle() throws {
        try runSession(extraTheme: true, struggleWords: 2)
    }

    @MainActor
    private func runSession(extraTheme: Bool, struggleWords: Int) throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-LearningInteractionUITest", "-LearningInteractionUITestReset", "-RealSessionUITest", "-RealSessionUITestNoSpeech"]
        if extraTheme { app.launchArguments += ["-development_interface_mode", "extraordinary"] }
        app.launch()

        let card = app.descendants(matching: .any)["learning-card-vocabulary"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 15))
        card.tap()
        XCTAssertTrue(app.navigationBars["Học từ vựng"].waitForExistence(timeout: 10))

        let start = app.buttons["review-start"]
        XCTAssertTrue(start.waitForExistence(timeout: 30), "Review list did not appear (no due words or not signed in)")
        snapshot(app, extraTheme ? "11-extra-review-list" : "01-review-list")
        var swipes = 0
        while !start.isHittable && swipes < 8 { app.swipeUp(); swipes += 1 }
        start.tap()

        var didRescue = struggleWords > 0
        var didHint = struggleWords > 0
        var strugglingAnswers: [String] = []
        var seenQuestions: [String: Int] = [:]
        var pronunciationTries = 0
        var shots: Set<String> = []

        for _ in 0..<200 {
            if app.otherElements["learning-word-results"].exists || app.staticTexts["Hoàn thành bài học!"].exists {
                break
            }
            if app.staticTexts["learning-attempt-score"].exists {
                if shots.insert("result").inserted { snapshot(app, "04-answer-card") }
                app.buttons["learning-result-ok"].tap()
                XCTAssertTrue(app.buttons["Tiếp tục"].waitForExistence(timeout: 5))
                snapshot(app, "04-vocabulary-review")
                app.buttons["Tiếp tục"].firstMatch.tap()
                continue
            }

            let marker = app.staticTexts["learning-debug-answer"]
            guard marker.waitForExistence(timeout: 20) else {
                if app.staticTexts["Hoàn thành bài học!"].waitForExistence(timeout: 30) { break }
                snapshot(app, "99-stuck")
                XCTFail("No question and no completion screen")
                return
            }
            let parts = marker.label.components(separatedBy: "::")
            let type = parts.first ?? ""
            let answer = parts.count > 1 ? parts[1] : ""
            let wordKey = (parts.count > 2 ? parts[2] : answer).lowercased()
            if !wordKey.isEmpty && strugglingAnswers.count < struggleWords && !strugglingAnswers.contains(wordKey) {
                strugglingAnswers.append(wordKey)
            }
            let questionKey = "\(type)|\(answer)"
            let seen = seenQuestions[questionKey, default: 0]
            seenQuestions[questionKey] = seen + 1
            let struggles = type != "pronunciation_example" && seen == 0
                && strugglingAnswers.contains(wordKey)
            if struggles {
                let giveUp = app.buttons["learning-give-up"]
                XCTAssertTrue(giveUp.waitForExistence(timeout: 5))
                giveUp.tap()
                continue
            }

            switch type {
            case "listen_and_type", "meaning_and_type":
                let field = app.textFields["learning-answer-field"]
                XCTAssertTrue(field.waitForExistence(timeout: 5))
                field.tap()
                if type == "listen_and_type" && !didRescue {
                    // A spelling slip on the first try exercises the rescue life.
                    field.typeText(answer + "x")
                    app.buttons["learning-check"].tap()
                    let rescue = app.buttons["learning-rescue"]
                    XCTAssertTrue(rescue.waitForExistence(timeout: 5))
                    snapshot(app, "03-rescue")
                    rescue.tap()
                    field.typeText(answer)
                    didRescue = true
                } else if type == "meaning_and_type" && !didHint {
                    app.buttons["learning-hint"].tap()
                    snapshot(app, "02-hint")
                    field.tap()
                    field.typeText(answer)
                    didHint = true
                } else {
                    field.typeText(answer)
                }
                app.buttons["learning-check"].tap()
            case "multiple_choice":
                let option = app.buttons["learning-option-\(answer)"]
                XCTAssertTrue(option.waitForExistence(timeout: 5))
                option.tap()
            case "sentence_scramble":
                for token in answer.split(separator: "|") {
                    let button = app.buttons["scramble-available-\(token)"].firstMatch
                    if !button.waitForExistence(timeout: 5) {
                        snapshot(app, "98-scramble-missing-\(token)")
                        print("SCRAMBLE answer=\(answer) available=\(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'scramble-available-'")).allElementsBoundByIndex.map(\.identifier))")
                        XCTFail("Missing scramble token \(token)")
                        return
                    }
                    button.tap()
                }
                app.buttons["learning-check"].tap()
            case "pronunciation_example":
                pronunciationTries += 1
                if pronunciationTries > 8 {
                    // The simulator cannot speak; finish with the debug path once only read-aloud is left.
                    finishWithDeveloperButton(app)
                    break
                }
                recordOnce(app)
            default:
                XCTFail("Unknown task type \(type)")
                return
            }
        }

        XCTAssertTrue(app.staticTexts["Hoàn thành bài học!"].waitForExistence(timeout: 60))
        let results = app.otherElements["learning-word-results"]
        _ = results.waitForExistence(timeout: 10)
        snapshot(app, extraTheme ? "15-extra-completion" : "05-completion")
        if results.exists { results.swipeUp() }
        snapshot(app, extraTheme ? "16-extra-completion-more" : "06-completion-more")
    }

    @MainActor
    private func recordOnce(_ app: XCUIApplication) {
        let mic = app.buttons["Bắt đầu thu âm"]
        guard mic.waitForExistence(timeout: 10) else { return }
        mic.tap()
        sleep(2)
        let stop = app.buttons["Dừng thu âm"]
        if stop.waitForExistence(timeout: 3) { stop.tap() }
        let check = app.buttons["Kiểm tra"].firstMatch
        if check.waitForExistence(timeout: 5), check.isEnabled { check.tap() }
        let next = app.buttons["Tiếp tục"].firstMatch
        if next.waitForExistence(timeout: 40) {
            snapshot(app, "pronunciation-result")
            next.tap()
        } else if app.alerts.firstMatch.exists {
            app.alerts.buttons.firstMatch.tap()
        }
    }

    @MainActor
    private func finishWithDeveloperButton(_ app: XCUIApplication) {
        let wrench = app.buttons["Hoàn tất phiên kiểm thử"]
        guard wrench.waitForExistence(timeout: 5) else { return }
        wrench.tap()
        let confirm = app.alerts.buttons["Lưu như đã hoàn thành"]
        if confirm.waitForExistence(timeout: 5) { confirm.tap() }
    }

    @MainActor
    private func snapshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
