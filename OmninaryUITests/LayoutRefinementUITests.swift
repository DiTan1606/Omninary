import XCTest

final class LayoutRefinementUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testCardGapsAndCompactLearningGrid() {
        for mode in ["ditandnary", "extraordinary"] {
            let app = XCUIApplication()
            app.launchArguments = ["-UITesting", "-LayoutRefinementUITest", "-LearningInteractionUITestReset", "-development_interface_mode", mode]
            app.launch()
            app.tabBars.buttons["Library"].tap()
            let vocabulary = app.buttons["library-vocabulary-card"]
            let listening = app.buttons["library-listening-card"]
            XCTAssertTrue(listening.waitForExistence(timeout: 10))
            let gap = listening.frame.minY - vocabulary.frame.maxY
            XCTAssertEqual(gap, 20, accuracy: 1)
            capture(app, "library-\(mode)")

            app.tabBars.buttons["Home"].tap()
            let streak = element(app, "home-streak-card")
            let energy = element(app, "home-energy-card")
            XCTAssertTrue(energy.waitForExistence(timeout: 5))
            XCTAssertEqual(energy.frame.minY - streak.frame.maxY, gap, accuracy: 1)
            capture(app, "home-\(mode)")

            app.tabBars.buttons["Learning"].tap()
            let words = element(app, "learning-card-vocabulary")
            let ears = element(app, "learning-card-listening")
            XCTAssertTrue(ears.waitForExistence(timeout: 5))
            XCTAssertEqual(ears.frame.minX - words.frame.maxX, 12, accuracy: 1)
            capture(app, "learning-\(mode)")
            words.tap()
            let review = element(app, "vocabulary-learning-review")
            XCTAssertTrue(review.waitForExistence(timeout: 10))
            let progress = element(app, "vocabulary-learning-progress")
            XCTAssertEqual(review.frame.minY - progress.frame.maxY, gap, accuracy: 1)
            capture(app, "vocabulary-learning-\(mode)")
            app.navigationBars.buttons.firstMatch.tap()

            app.tabBars.buttons["My Omni"].tap()
            let profile = element(app, "my-omni-profile-card")
            XCTAssertTrue(profile.waitForExistence(timeout: 5))
            let next = element(app, mode == "extraordinary" ? "my-omni-points-card" : "my-omni-upgrade-card")
            XCTAssertTrue(next.exists)
            XCTAssertEqual(next.frame.minY - profile.frame.maxY, gap, accuracy: 1)
            capture(app, "my-omni-\(mode)")
            app.terminate()
        }
    }

    @MainActor private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
