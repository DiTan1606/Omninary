import XCTest

final class SettingUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSettingLayoutInBothInterfaces() {
        for mode in ["ditandnary", "extraordinary"] {
            let app = settingsApp(mode: mode)
            app.launch()
            XCTAssertTrue(app.navigationBars["Setting"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.switches["settings-daily-reminder"].exists)
            XCTAssertFalse(app.staticTexts["Lặp lại mỗi ngày theo giờ trên thiết bị này."].exists)
            XCTAssertFalse(app.buttons["Mở cài đặt thông báo"].exists)
            XCTAssertTrue(app.buttons["settings-switch-interface"].exists)
            if !app.buttons["settings-sign-out"].isHittable { app.swipeUp() }
            XCTAssertTrue(app.buttons["settings-sign-out"].isHittable)
            for title in ["Phát âm từ vựng", "Không gian học tập", "Về Omninary", "Tài khoản", "Mô phỏng Chuỗi"] {
                XCTAssertFalse(app.staticTexts[title].exists)
            }
            XCTAssertFalse(app.segmentedControls["settings-speech-speed"].exists)
            XCTAssertFalse(app.buttons["settings-reset-learning-layout"].exists)
            let image = XCTAttachment(screenshot: app.screenshot())
            image.name = "setting-\(mode)"
            image.lifetime = .keepAlways
            add(image)
            app.terminate()
        }
    }

    @MainActor
    func testDevelopmentInterfaceSwitchPersists() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-LayoutRefinementUITest"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Setting"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Setting"].tap()
        let button = app.buttons["settings-switch-interface"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        let original = button.label
        let changed = original.contains("Extra") ? "Chuyển sang Ditan" : "Chuyển sang Extra"
        button.tap()
        XCTAssertTrue(app.navigationBars["Setting"].waitForExistence(timeout: 5))
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        XCTAssertEqual(button.label, changed)
        app.terminate()
        app.launch()
        app.tabBars.buttons["Setting"].tap()
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        XCTAssertEqual(button.label, changed)
        button.tap()
        XCTAssertEqual(button.label, original)
    }

    @MainActor
    func testSignOutCanBeCancelled() {
        let app = settingsApp(mode: "ditandnary")
        app.launch()
        let button = app.buttons["settings-sign-out"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        button.tap()
        let confirmation = app.alerts["Đăng xuất khỏi Omninary?"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 3))
        confirmation.buttons["Huỷ"].tap()
        XCTAssertFalse(confirmation.exists)
        XCTAssertTrue(button.isHittable)
    }

    @MainActor
    private func settingsApp(mode: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-SettingUITest", "-development_interface_mode", mode]
        return app
    }
}
