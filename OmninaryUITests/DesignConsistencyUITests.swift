import XCTest

final class DesignConsistencyUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testSharedComponentsInBothThemes() {
        for mode in ["ditandnary", "extraordinary"] {
            let app = launch(mode: mode)
            let primary = app.buttons["design-primary-action"]
            XCTAssertTrue(primary.waitForExistence(timeout: 10))
            XCTAssertTrue(primary.isHittable)
            primary.tap()
            XCTAssertEqual(app.staticTexts["design-action-count"].label, "Đã bấm 1 lần")
            app.buttons["design-secondary-action"].tap()
            XCTAssertEqual(app.staticTexts["design-action-count"].label, "Đã bấm 0 lần")
            capture(app, "design-\(mode)-top")
            app.swipeUp()
            let disabled = app.buttons["design-disabled-action"]
            XCTAssertTrue(disabled.exists)
            XCTAssertFalse(disabled.isEnabled)
            XCTAssertTrue(app.buttons["Xóa mục mẫu"].isHittable)
            capture(app, "design-\(mode)-bottom")
            app.terminate()
        }
    }

    @MainActor
    func testLargeTextKeepsActionsReachable() {
        let app = launch(mode: "extraordinary", largeText: true)
        let primary = app.buttons["design-primary-action"]
        XCTAssertTrue(primary.waitForExistence(timeout: 10))
        XCTAssertTrue(primary.isHittable)
        XCTAssertTrue(app.buttons["design-secondary-action"].isHittable)
        XCTAssertGreaterThan(primary.frame.height, 44)
        XCTAssertLessThanOrEqual(primary.frame.maxY, app.frame.maxY)
        primary.tap()
        capture(app, "design-compact-large-text")
    }

    @MainActor private func launch(mode: String, largeText: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-DesignConsistencyUITest", "-development_interface_mode", mode]
        if largeText { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        return app
    }

    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name
        image.lifetime = .keepAlways
        add(image)
    }
}
