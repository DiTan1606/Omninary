import XCTest

final class InterfacePolishUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testLibraryCardsOpenFromEmptySpace() {
        for mode in ["ditandnary", "extraordinary"] {
            let app = XCUIApplication()
            app.launchArguments = ["-UITesting", "-InterfacePolishUITest", "-development_interface_mode", mode]
            app.launch()
            app.tabBars.buttons["Thư viện"].tap()
            let vocabulary = app.buttons["library-vocabulary-card"]
            XCTAssertTrue(vocabulary.waitForExistence(timeout: 5))
            vocabulary.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.25)).tap()
            XCTAssertTrue(app.navigationBars["My Vocabulary"].waitForExistence(timeout: 5))
            app.navigationBars.buttons.firstMatch.tap()
            let listening = app.buttons["library-listening-card"]
            XCTAssertTrue(listening.waitForExistence(timeout: 5))
            listening.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.25)).tap()
            XCTAssertTrue(app.navigationBars["My Listening"].waitForExistence(timeout: 5))
            app.terminate()
        }
    }

    @MainActor
    func testFloatingExploreActionsInBothThemes() {
        for mode in ["ditandnary", "extraordinary"] {
            let app = XCUIApplication()
            app.launchArguments = ["-UITesting", "-InterfacePolishUITest", "-development_interface_mode", mode]
            app.launch()
            app.buttons["Xem bộ từ mẫu"].tap()
            let action = app.buttons["explore-download-action"]
            XCTAssertTrue(action.waitForExistence(timeout: 5))
            XCTAssertTrue(action.isHittable)
            XCTAssertGreaterThanOrEqual(action.frame.minX, 15)
            XCTAssertLessThanOrEqual(action.frame.maxX, app.frame.width - 15)
            capture(app, name: "floating-vocabulary-\(mode)")
            app.navigationBars.buttons.firstMatch.tap()
            app.buttons["Xem seri mẫu"].tap()
            XCTAssertTrue(action.waitForExistence(timeout: 5))
            XCTAssertTrue(action.isHittable)
            XCTAssertGreaterThanOrEqual(action.frame.height, 52)
            capture(app, name: "floating-listening-\(mode)")
            app.terminate()
        }
    }

    @MainActor
    func testCalendarExploreAndLibraryInBothInterfaces() {
        for mode in ["ditandnary", "extraordinary"] {
            let app = XCUIApplication()
            app.launchArguments = ["-UITesting", "-InterfacePolishUITest", "-development_interface_mode", mode]
            app.launch()
            XCTAssertTrue(app.staticTexts["Lịch học tập"].waitForExistence(timeout: 10))
            capture(app, name: "calendar-\(mode)")
            app.buttons["Xem bộ từ mẫu"].tap()
            XCTAssertTrue(app.staticTexts["apple"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["/ˈæp.əl/"].exists)
            XCTAssertTrue(app.staticTexts["Từ loại: noun"].exists)
            XCTAssertTrue(app.staticTexts["Quả táo"].exists)
            XCTAssertTrue(app.staticTexts["Từ loại: verb"].exists)
            XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label == %@", "Mới")).count, 1)
            capture(app, name: "explore-\(mode)")
            app.navigationBars.buttons.firstMatch.tap()
            app.tabBars.buttons["Thư viện"].tap()
            XCTAssertTrue(app.staticTexts["My Vocabulary"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["My Listening"].exists)
            XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Bộ từ đã tải")).firstMatch.exists)
            XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Seri đã tải")).firstMatch.exists)
            capture(app, name: "library-\(mode)")
            app.terminate()
        }
    }

    @MainActor
    private func capture(_ app: XCUIApplication, name: String) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name
        image.lifetime = .keepAlways
        add(image)
    }
}
