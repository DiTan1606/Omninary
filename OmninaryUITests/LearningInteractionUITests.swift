import XCTest

final class LearningInteractionUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testBlankSpaceOpensEveryWidgetSize() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-LearningInteractionUITest", "-LearningInteractionUITestReset", "-development_interface_mode", "extraordinary"]
        app.launch()
        for size in ["1×1", "2×2", "4×2", "4×4"] {
            let card = app.descendants(matching: .any)["learning-card-vocabulary"].firstMatch
            XCTAssertTrue(card.waitForExistence(timeout: 10))
            card.press(forDuration: 1.0)
            app.buttons["learning-card-resize-vocabulary"].tap()
            app.buttons[size].tap()
            app.buttons["Xong"].tap()
            let image = XCTAttachment(screenshot: app.screenshot())
            image.name = "learning-size-\(size)"
            image.lifetime = .keepAlways
            add(image)
            card.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.15)).tap()
            XCTAssertTrue(app.navigationBars["Học từ vựng"].waitForExistence(timeout: 5))
            app.navigationBars.buttons.firstMatch.tap()
        }
    }

    @MainActor
    func testShortHoldOpensLearningPage() {
        let app = launchLearning(reset: true)
        let card = app.descendants(matching: .any)["learning-card-vocabulary"]
        XCTAssertTrue(card.waitForExistence(timeout: 10))

        card.press(forDuration: 0.65)

        XCTAssertTrue(app.navigationBars["Học từ vựng"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Xong"].exists)
    }

    @MainActor
    func testHoldEditsDragSavesAndLocks() {
        let app = launchLearning(reset: true)
        let card = app.descendants(matching: .any)["learning-card-vocabulary"]
        let otherCard = app.descendants(matching: .any)["learning-card-listening"]
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        XCTAssertTrue(otherCard.exists)
        let originalX = card.frame.minX

        card.press(forDuration: 1.0)
        XCTAssertTrue(app.buttons["Xong"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["learning-card-resize-vocabulary"].exists)
        XCTAssertTrue(app.buttons["learning-card-remove-vocabulary"].exists)

        card.press(forDuration: 0.05, thenDragTo: otherCard)
        XCTAssertGreaterThan(card.frame.minX, originalX + 10)

        app.buttons["Xong"].tap()
        XCTAssertFalse(app.buttons["Xong"].exists)
        let savedX = card.frame.minX

        app.terminate()
        app.launchArguments = ["-UITesting", "-LearningInteractionUITest"]
        app.launch()
        let restoredCard = app.descendants(matching: .any)["learning-card-vocabulary"]
        XCTAssertTrue(restoredCard.waitForExistence(timeout: 10))
        XCTAssertEqual(restoredCard.frame.minX, savedX, accuracy: 5)

        restoredCard.tap()
        XCTAssertTrue(app.navigationBars["Học từ vựng"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testResizeAndRemoveOnlyInEditingMode() {
        let app = launchLearning(reset: true)
        let card = app.descendants(matching: .any)["learning-card-vocabulary"]
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["learning-card-resize-vocabulary"].exists)
        XCTAssertFalse(app.buttons["learning-card-remove-vocabulary"].exists)
        let originalWidth = card.frame.width

        card.press(forDuration: 1.0)
        let resize = app.buttons["learning-card-resize-vocabulary"]
        XCTAssertTrue(resize.waitForExistence(timeout: 5))
        resize.tap()
        app.buttons["4×2"].tap()
        XCTAssertGreaterThan(card.frame.width, originalWidth + 20)

        app.buttons["learning-card-remove-vocabulary"].tap()
        XCTAssertFalse(card.exists)
        app.buttons["Xong"].tap()

        app.terminate()
        app.launchArguments = ["-UITesting", "-LearningInteractionUITest"]
        app.launch()
        XCTAssertFalse(app.descendants(matching: .any)["learning-card-vocabulary"].exists)
    }

    @MainActor
    func testFullCardsCanBeScrolledBySwipingOnCard() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-LearningInteractionUITest", "-LearningInteractionUITestReset", "-LearningInteractionUITestFullGrid"]
        app.launch()
        let card = app.descendants(matching: .any)["learning-card-vocabulary"]
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        let initialY = card.frame.minY

        card.swipeUp()

        let scrolledY = card.frame.minY
        XCTAssertLessThan(scrolledY, initialY - 30)
        let secondCard = app.descendants(matching: .any)["learning-card-listening"]
        let swipeStart = secondCard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
        swipeStart.press(forDuration: 0.05, thenDragTo: swipeStart.withOffset(CGVector(dx: 0, dy: 220)))
        XCTAssertGreaterThan(card.frame.minY, scrolledY + 30)
        XCTAssertFalse(app.buttons["Xong"].exists)
        XCTAssertFalse(app.navigationBars["Học từ vựng"].exists)
    }

    @MainActor
    private func launchLearning(reset: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-LearningInteractionUITest"]
        if reset { app.launchArguments.append("-LearningInteractionUITestReset") }
        app.launch()
        return app
    }
}
