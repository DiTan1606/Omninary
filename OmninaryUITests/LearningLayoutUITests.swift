import XCTest

final class LearningLayoutUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testFeedbackRequiresOKThenVocabularyReviewInBothThemes() {
        for theme in ["ditandnary", "extraordinary"] {
            let app = launch(theme: theme, screen: "Sequence")
            for exercise in ["Type", "Listen", "Scramble", "Choice"] {
                let hint = app.buttons["learning-hint"]
                XCTAssertTrue(hint.waitForExistence(timeout: 10))
                let originalHintY = hint.frame.minY
                hint.tap()
                XCTAssertTrue(app.descendants(matching: .any)["learning-hint-panel"].firstMatch.exists)
                XCTAssertEqual(hint.frame.minY, originalHintY, accuracy: 2)
                XCTAssertTrue(app.buttons["learning-give-up"].isHittable)
                if exercise == "Type" || exercise == "Listen" {
                    let field = app.textFields["learning-answer-field"]
                    let panel = app.descendants(matching: .any)["learning-hint-panel"].firstMatch
                    XCTAssertTrue(field.isHittable)
                    XCTAssertLessThanOrEqual(field.frame.maxY, panel.frame.minY)
                }
                snapshot(app, "\(theme)-\(exercise)-hint")
                switch exercise {
                case "Listen":
                    let field = app.textFields["learning-answer-field"]
                    field.tap()
                    field.typeText("apple")
                    XCTAssertTrue(app.buttons["learning-check"].isHittable)
                    XCTAssertTrue(hint.isHittable)
                    snapshot(app, "\(theme)-keyboard")
                    app.buttons["learning-check"].tap()
                case "Scramble":
                    for token in ["eats", "an", "apple", "every", "morning"] {
                        app.buttons["scramble-available-\(token)"].tap()
                    }
                    app.buttons["learning-check"].tap()
                case "Choice":
                    app.buttons["learning-option-apple"].tap()
                default:
                    app.buttons["learning-give-up"].tap()
                }
                let ok = app.buttons["learning-result-ok"]
                XCTAssertTrue(ok.waitForExistence(timeout: 5))
                XCTAssertFalse(app.buttons["Tiếp tục"].exists)
                snapshot(app, "\(theme)-\(exercise)-result")
                ok.tap()
                let next = app.buttons["Tiếp tục"]
                XCTAssertTrue(next.waitForExistence(timeout: 5))
                XCTAssertTrue(next.isHittable)
                XCTAssertTrue(app.staticTexts["vocabulary-short-meaning"].exists)
                snapshot(app, "\(theme)-\(exercise)-word-review")
                next.tap()
                XCTAssertTrue(hint.waitForExistence(timeout: 5))
                XCTAssertFalse(ok.exists)
            }
            app.terminate()
        }
    }

    @MainActor
    func testReviewListScrollsWhileStartRemainsVisibleInBothThemes() {
        for theme in ["ditandnary", "extraordinary"] {
            let app = launch(theme: theme, screen: "Review")
            let review = app.otherElements["vocabulary-learning-review"]
            XCTAssertTrue(review.waitForExistence(timeout: 10))
            // The page gutter stays outside the nested word list.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.85))
                .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.12)))
            let start = app.buttons["review-start"]
            XCTAssertTrue(start.isHittable)
            XCTAssertFalse(app.buttons["review-pick-priority"].exists)
            let initialY = start.frame.minY
            let list = review.scrollViews.firstMatch
            XCTAssertTrue(list.exists)
            list.swipeUp()
            let firstWord = app.buttons["review-word-apple"]
            XCTAssertFalse(firstWord.exists && firstWord.isHittable)
            XCTAssertTrue(start.isHittable)
            XCTAssertEqual(start.frame.minY, initialY, accuracy: 2)
            snapshot(app, "\(theme)-bounded-review")
            app.terminate()
        }
    }

    @MainActor
    private func launch(theme: String, screen: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-LearningLayoutUITest", "-LearningLayout\(screen)",
                               "-development_interface_mode", theme]
        app.launch()
        return app
    }

    @MainActor
    private func snapshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
