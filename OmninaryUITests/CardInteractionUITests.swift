import XCTest

final class CardInteractionUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testHomeAndOmniCardsAcceptBlankSpace() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-LayoutRefinementUITest", "-development_interface_mode", "ditandnary"]
        app.launch()
        let vocabulary = app.buttons["home-explore-vocabulary"]
        XCTAssertTrue(vocabulary.waitForExistence(timeout: 10))
        for _ in 0..<3 where !vocabulary.isHittable || vocabulary.frame.maxY > app.tabBars.firstMatch.frame.minY { app.swipeUp() }
        vocabulary.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.96)).tap()
        XCTAssertTrue(app.navigationBars["Khám phá Từ vựng"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        let listening = app.buttons["home-explore-listening"]
        for _ in 0..<3 where !listening.isHittable || listening.frame.maxY > app.tabBars.firstMatch.frame.minY { app.swipeUp() }
        listening.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.96)).tap()
        XCTAssertTrue(app.navigationBars["Khám phá Bài luyện nghe"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        app.tabBars.buttons["My Omni"].tap()
        let upgrade = app.buttons["my-omni-upgrade-card"]
        XCTAssertTrue(upgrade.waitForExistence(timeout: 5))
        for _ in 0..<3 where upgrade.frame.maxY > app.tabBars.firstMatch.frame.minY { app.swipeUp() }
        upgrade.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.95)).tap()
        let monthly = app.buttons["upgrade-plan-monthly"]
        for _ in 0..<3 where !monthly.isHittable { app.swipeUp() }
        XCTAssertTrue(monthly.waitForExistence(timeout: 5))
        monthly.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.9)).tap()
        XCTAssertEqual(monthly.value as? String, "Đã chọn")
        if !app.buttons["Để sau"].isHittable { app.swipeUp() }
        app.buttons["Để sau"].tap()
        let points = app.buttons["my-omni-points-card"]
        XCTAssertTrue(points.waitForExistence(timeout: 5))
        for _ in 0..<3 where points.frame.maxY > app.tabBars.firstMatch.frame.minY { app.swipeUp() }
        points.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.95)).tap()
        let package = app.buttons["top-up-package-pkg_1000"]
        XCTAssertTrue(package.waitForExistence(timeout: 5))
        package.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.9)).tap()
        XCTAssertEqual(package.value as? String, "Đã chọn")
    }
}
