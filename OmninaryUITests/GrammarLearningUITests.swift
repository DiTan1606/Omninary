import XCTest

final class GrammarLearningUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testGrammarNavigationAndCloudRetryInBothAppearances() {
        for appearance in ["light", "dark"] {
            let app = XCUIApplication()
            app.launchArguments = ["-UITesting", "-GrammarUITest", "-appearance_mode", appearance]
            app.launch()
            let grammar = app.buttons["learning-v2-grammar"]
            XCTAssertTrue(grammar.waitForExistence(timeout: 12))
            XCTAssertTrue(grammar.isHittable)
            XCTAssertLessThan(app.buttons["learning-v2-vocab"].frame.midY, grammar.frame.midY)
            XCTAssertLessThan(grammar.frame.midY, app.buttons["learning-v2-listen"].frame.midY)
            capture(app, "grammar-\(appearance)-learning")

            // Open Gram directly from Learning in the current five-tab shell.
            grammar.tap()
            XCTAssertTrue(app.buttons["grammar-stage-A1"].waitForExistence(timeout: 5))
            for stage in ["A1", "A2", "B1", "B2", "C1", "C2"] {
                XCTAssertTrue(app.buttons["grammar-stage-\(stage)"].exists)
            }
            capture(app, "grammar-\(appearance)-stages")
            // A2 stays locked until every A1 topic is passed.
            XCTAssertFalse(app.buttons["grammar-stage-A2"].isEnabled)
            app.buttons["grammar-stage-A1"].tap()
            let first = app.buttons["grammar-topic-A1.1"]
            XCTAssertTrue(first.waitForExistence(timeout: 5))
            XCTAssertTrue(first.isEnabled)
            XCTAssertTrue(app.descendants(matching: .any)["grammar-topic-A1.2"].exists)
            capture(app, "grammar-\(appearance)-a1")
            first.tap()
            // The navigation fixture has no cloud credentials or offline lesson fallback.
            // Real narration and storage access are checked with the user's account on a device.
            let retry = app.buttons["Mở lại bài học"]
            XCTAssertTrue(retry.waitForExistence(timeout: 8))
            XCTAssertTrue(app.buttons["Về lộ trình"].exists)
            capture(app, "grammar-\(appearance)-cloud-retry")
            app.buttons["Về lộ trình"].tap()
            XCTAssertTrue(app.buttons["grammar-topic-A1.1"].waitForExistence(timeout: 5))
            app.terminate()
        }
    }

    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
