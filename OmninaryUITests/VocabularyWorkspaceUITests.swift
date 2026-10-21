import XCTest

final class VocabularyWorkspaceUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testBlankPaddingAndMenuKeepSeparateActions() {
        for mode in ["ditandnary", "extraordinary"] {
            let app = XCUIApplication()
            app.launchArguments = ["-UITesting", "-VocabularyWorkspaceUITest", "-development_interface_mode", mode]
            app.launch()
            let folder = app.buttons["vocabulary-folder-preview-exam"]
            XCTAssertTrue(folder.waitForExistence(timeout: 10))
            folder.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.94)).tap()
            XCTAssertTrue(app.navigationBars["IELTS"].waitForExistence(timeout: 5))
            app.navigationBars.buttons.firstMatch.tap()
            let word = app.buttons["vocabularyPreview-bank-finance"]
            XCTAssertTrue(word.waitForExistence(timeout: 5))
            word.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.5)).tap()
            XCTAssertTrue(app.staticTexts["vocabularyPreviewTitle"].waitForExistence(timeout: 5))
            app.buttons["Đóng thẻ từ"].tap()
            word.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.2)).tap()
            XCTAssertTrue(app.buttons["Di chuyển đến bộ từ…"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.staticTexts["vocabularyPreviewTitle"].exists)
            app.navigationBars.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            app.buttons["Chọn"].tap()
            word.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.5)).tap()
            XCTAssertEqual(word.value as? String, "Đã chọn")
            word.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.5)).tap()
            XCTAssertEqual(word.value as? String, "Chưa chọn")
            app.terminate()
        }
    }

    @MainActor
    func testExtraVocabularyPreviewLayout() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-VocabularyWorkspaceUITest", "-development_interface_mode", "extraordinary"]
        app.launch()
        XCTAssertTrue(app.staticTexts["IELTS"].firstMatch.waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Bờ sông"].exists)
        XCTAssertTrue(app.staticTexts["Gửi tiền vào ngân hàng"].exists)
        let rootImage = XCTAttachment(screenshot: app.screenshot())
        rootImage.name = "Kho từ vựng tại trang gốc"
        rootImage.lifetime = .keepAlways
        add(rootImage)
        app.buttons["Chọn"].tap()
        XCTAssertTrue(app.buttons["Chọn tất cả"].waitForExistence(timeout: 3))
        let selectionImage = XCTAttachment(screenshot: app.screenshot())
        selectionImage.name = "Thanh chọn nhiều nổi trong Extra"
        selectionImage.lifetime = .keepAlways
        add(selectionImage)
        app.buttons["Xong"].tap()
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.925)).tap()
        XCTAssertTrue(app.buttons["Tạo bộ từ"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Tạo từ mới"].exists)
        let menuImage = XCTAttachment(screenshot: app.screenshot())
        menuImage.name = "Menu thêm cạnh dấu cộng"
        menuImage.lifetime = .keepAlways
        add(menuImage)
        // iOS 26 may present this as a popover without a Cancel button.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.18)).tap()
        XCTAssertTrue(app.staticTexts["Ngân hàng"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Ngân hàng"].exists)
        let folderImage = XCTAttachment(screenshot: app.screenshot())
        folderImage.name = "Các từ vựng trong bộ từ"
        folderImage.lifetime = .keepAlways
        add(folderImage)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.925)).tap()
        XCTAssertTrue(app.buttons["Tạo từ mới"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Tạo bộ từ"].exists)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        app.buttons["vocabularyPreview-bank-finance"].tap()
        XCTAssertTrue(app.staticTexts["vocabularyPreviewTitle"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["vocabularyPreviewTitle"].label, "bank")
        XCTAssertTrue(app.staticTexts["Cấp 4"].exists)
        XCTAssertTrue(app.buttons["Đóng thẻ từ"].exists)
        XCTAssertFalse(app.staticTexts["TỪ VỰNG"].exists)
        XCTAssertFalse(app.navigationBars["bank"].exists)
        let countdown = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Ôn lại sau:")).firstMatch
        XCTAssertTrue(countdown.waitForExistence(timeout: 5))
        XCTAssertFalse(countdown.isEnabled)
        let detailImage = XCTAttachment(screenshot: app.screenshot())
        detailImage.name = "Chi tiết Extra với nút đếm ngược"
        detailImage.lifetime = .keepAlways
        add(detailImage)
        closePreview(app)
        XCTAssertTrue(app.navigationBars["IELTS"].waitForExistence(timeout: 5))
        app.buttons["vocabularyPreview-bank-finance"].press(forDuration: 1)
        XCTAssertTrue(countdown.waitForExistence(timeout: 5))
        app.buttons["Đóng thẻ từ"].tap()
        XCTAssertTrue(app.buttons["vocabularyPreview-bank-finance"].waitForExistence(timeout: 5))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.09)).tap()
        verifyOtherLearningStates(app)
    }
    @MainActor
    func testDitanVocabularyPreviewLayout() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-VocabularyWorkspaceUITest", "-development_interface_mode", "ditandnary"]
        app.launch()
        XCTAssertTrue(app.buttons["vocabularyPreview-bank-finance"].waitForExistence(timeout: 15))
        app.buttons["vocabularyPreview-bank-finance"].tap()
        let countdown = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Ôn lại sau:")).firstMatch
        XCTAssertTrue(countdown.waitForExistence(timeout: 5))
        XCTAssertFalse(countdown.isEnabled)
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "Thẻ chi tiết giữa màn hình Ditan"
        image.lifetime = .keepAlways
        add(image)
        closePreview(app)
        verifyOtherLearningStates(app)
    }

    @MainActor
    func testExtraSwipeVocabularyPreview() {
        let app = launchSwipePreview(mode: "extraordinary")
        verifyRootSwiping(app)
        closePreview(app)

        let search = app.textFields["Tìm bộ từ hoặc từ"]
        search.tap()
        search.typeText("bank")
        app.buttons["vocabularyPreview-bank-finance"].tap()
        assertPosition(app, 1, 3)
        swipePreview(app, next: false)
        assertPosition(app, 1, 3)
        swipePreview(app, next: true)
        assertPosition(app, 2, 3)
        swipePreview(app, next: true)
        assertPosition(app, 3, 3)
        swipePreview(app, next: true)
        assertPosition(app, 3, 3)
        closePreview(app)

        // Launch afresh to restore the unfiltered list and test collection boundaries.
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["IELTS"].waitForExistence(timeout: 15))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.18)).tap()
        app.buttons["vocabularyPreview-bank-finance"].tap()
        assertPosition(app, 1, 1)
        swipePreview(app, next: true)
        assertPosition(app, 1, 1)
        swipePreview(app, next: false)
        assertPosition(app, 1, 1)
        closePreview(app)
        XCTAssertTrue(app.navigationBars["IELTS"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testDitanSwipeVocabularyPreview() {
        let app = launchSwipePreview(mode: "ditandnary")
        verifyRootSwiping(app)
        closePreview(app)
        XCTAssertTrue(app.buttons["vocabularyPreview-bank-finance"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testPreviewSwipingAndCollectionSummary() {
        for mode in ["ditandnary", "extraordinary"] {
            let app = launchSwipePreview(mode: mode)
            XCTAssertTrue(app.staticTexts["vocabularyPreviewPosition"].exists)
            swipePreview(app, next: true)
            assertPosition(app, 3, 4)
            swipePreview(app, next: false)
            assertPosition(app, 2, 4)
            swipePreview(app, next: false)
            assertPosition(app, 1, 4)
            XCTAssertFalse(app.buttons["Từ trước"].exists)
            let card = XCTAttachment(screenshot: app.screenshot())
            card.name = "word-card-\(mode)"
            card.lifetime = .keepAlways
            add(card)
            app.buttons["Đóng thẻ từ"].tap()
            XCTAssertTrue(app.buttons["vocabularyPreview-bank-finance"].waitForExistence(timeout: 5))
            app.buttons["vocabulary-folder-preview-exam"].tap()
            XCTAssertTrue(app.staticTexts["Tổng quan bộ từ"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.staticTexts["vocabularyCollectionTotal"].label, "1 từ")
            let chartPicker = app.segmentedControls["vocabularyCollectionChartPicker"]
            XCTAssertTrue(chartPicker.exists)
            let cefrChoice = chartPicker.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "CEFR")).firstMatch
            let cefrChart = app.descendants(matching: .any)["vocabularyCollectionCEFRChart"].firstMatch
            let learningChart = app.descendants(matching: .any)["vocabularyCollectionLearningChart"].firstMatch
            XCTAssertTrue(cefrChoice.isSelected)
            XCTAssertTrue(cefrChart.exists)
            XCTAssertFalse(learningChart.exists)
            chartPicker.buttons["Cấp độ học"].tap()
            XCTAssertTrue(learningChart.waitForExistence(timeout: 3))
            XCTAssertFalse(cefrChart.exists)
            XCTAssertEqual(app.staticTexts["vocabularyCollectionTotal"].label, "1 từ")
            let learning = XCTAttachment(screenshot: app.screenshot())
            learning.name = "collection-learning-switch-\(mode)"
            learning.lifetime = .keepAlways
            add(learning)
            cefrChoice.tap()
            XCTAssertTrue(cefrChart.waitForExistence(timeout: 3))
            XCTAssertFalse(learningChart.exists)
            XCTAssertFalse(app.staticTexts["Từ loại"].exists)
            let collection = XCTAttachment(screenshot: app.screenshot())
            collection.name = "collection-cefr-switch-\(mode)"
            collection.lifetime = .keepAlways
            add(collection)
            let search = app.textFields["Tìm bộ từ hoặc từ"]
            search.tap()
            search.typeText("no-match")
            app.swipeUp()
            XCTAssertTrue(app.staticTexts["Không tìm thấy"].waitForExistence(timeout: 3))
            XCTAssertEqual(app.staticTexts["vocabularyCollectionTotal"].label, "1 từ")
            app.terminate()
        }
    }

    @MainActor
    func testCompactVocabularyCardLayout() {
        for mode in ["ditandnary", "extraordinary"] {
            let app = launchSwipePreview(mode: mode)
            let close = app.buttons["Đóng thẻ từ"]
            XCTAssertTrue(close.isHittable)
            XCTAssertTrue(app.buttons["vocabulary-learning-action"].isHittable)
            XCTAssertFalse(app.buttons["Từ tiếp theo"].exists)
            let hint = app.staticTexts["vocabularyPreviewPosition"]
            XCTAssertTrue(hint.isHittable)
            XCTAssertGreaterThanOrEqual(close.frame.minY, 20)
            XCTAssertLessThanOrEqual(hint.frame.maxY, app.frame.height - 10)
            let image = XCTAttachment(screenshot: app.screenshot())
            image.name = "compact-word-card-\(mode)"
            image.lifetime = .keepAlways
            add(image)
            closePreview(app)
            XCTAssertTrue(app.buttons["vocabularyPreview-bank-finance"].waitForExistence(timeout: 5))
            app.terminate()
        }
    }

    @MainActor
    private func launchSwipePreview(mode: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-VocabularyWorkspaceUITest", "-development_interface_mode", mode]
        app.launch()
        XCTAssertTrue(app.buttons["vocabularyPreview-bank-finance"].waitForExistence(timeout: 15))
        app.buttons["vocabularyPreview-bank-finance"].tap()
        return app
    }

    @MainActor
    private func assertPosition(_ app: XCUIApplication, _ position: Int, _ count: Int,
                                file: StaticString = #filePath, line: UInt = #line) {
        let marker = app.staticTexts["vocabularyPreviewPosition"]
        let expected = "Vuốt trái hoặc phải để chuyển từ - Từ \(position) trên \(count)"
        let predicate = NSPredicate(format: "label == %@", expected)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: marker)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed, file: file, line: line)
    }

    @MainActor
    private func swipePreview(_ app: XCUIApplication, next: Bool) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: next ? 0.82 : 0.18, dy: 0.48))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: next ? 0.18 : 0.82, dy: 0.48))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    @MainActor
    private func verifyRootSwiping(_ app: XCUIApplication) {
        // Four vocabulary records, including three spelled "bank"; the IELTS folder is excluded.
        assertPosition(app, 2, 4)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.68))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.32)))
        assertPosition(app, 2, 4)
        swipePreview(app, next: true)
        assertPosition(app, 3, 4)
        XCTAssertTrue(app.buttons["Ôn tập ngay"].exists)
        XCTAssertTrue(app.staticTexts["Bờ sông"].exists)
        swipePreview(app, next: true)
        assertPosition(app, 4, 4)
        XCTAssertTrue(app.buttons["Đưa từ này vào học"].exists)
        swipePreview(app, next: true)
        assertPosition(app, 4, 4)
        swipePreview(app, next: false)
        assertPosition(app, 3, 4)
        swipePreview(app, next: false)
        assertPosition(app, 2, 4)
        XCTAssertTrue(app.staticTexts["vocabulary-word-form"].firstMatch.isHittable)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Ôn lại sau:")).firstMatch.exists)
        swipePreview(app, next: false)
        assertPosition(app, 1, 4)
        XCTAssertEqual(app.staticTexts["vocabularyPreviewTitle"].label, "adapt")
        swipePreview(app, next: false)
        assertPosition(app, 1, 4)
    }

    @MainActor
    private func closePreview(_ app: XCUIApplication) {
        app.buttons["Đóng thẻ từ"].tap()
    }

    @MainActor
    private func verifyOtherLearningStates(_ app: XCUIApplication) {
        let unlearned = app.buttons["vocabularyPreview-bank-third"]
        XCTAssertTrue(unlearned.waitForExistence(timeout: 5))
        unlearned.tap()
        XCTAssertTrue(app.buttons["Đưa từ này vào học"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Đưa từ này vào học"].isEnabled)
        closePreview(app)
        app.buttons["vocabularyPreview-bank-river"].press(forDuration: 1)
        XCTAssertTrue(app.buttons["Ôn tập ngay"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Ôn tập ngay"].isEnabled)
        closePreview(app)
        XCTAssertTrue(app.buttons["vocabularyPreview-bank-river"].waitForExistence(timeout: 5))
    }
}
