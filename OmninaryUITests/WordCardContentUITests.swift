import XCTest

final class WordCardContentUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testVisibleDefinitionsAndSwipeOnlyFooterInBothThemes() {
        for mode in ["ditandnary", "extraordinary"] {
            let app = XCUIApplication()
            app.launchArguments = ["-UITesting", "-VocabularyWorkspaceUITest", "-WordCardContentUITest",
                                   "-development_interface_mode", mode]
            app.launch()
            let card = app.buttons["vocabularyPreview-layout-lay-off"]
            XCTAssertTrue(card.waitForExistence(timeout: 10))
            card.tap()
            let title = app.staticTexts["vocabularyPreviewTitle"]
            XCTAssertTrue(title.waitForExistence(timeout: 5))
            XCTAssertEqual(title.label, "lay off")
            let close = app.buttons["Đóng thẻ từ"]
            let status = app.staticTexts["vocabulary-card-status"]
            XCTAssertLessThan(abs(close.frame.midY - status.frame.midY), 2)
            XCTAssertFalse(app.buttons["vocabulary-word-audio"].exists)
            let ipa = app.staticTexts["vocabulary-ipa"]
            let form = app.staticTexts["vocabulary-word-form"]
            let level = app.staticTexts["vocabulary-cefr"]
            XCTAssertLessThan(ipa.frame.minX, form.frame.minX)
            XCTAssertLessThan(form.frame.minX, level.frame.minX)
            for region in [title, status, ipa, form, level] {
                region.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                XCTAssertTrue(close.exists)
                XCTAssertEqual(title.label, "lay off")
            }
            let origin = app.coordinate(withNormalizedOffset: .zero)
            // Phần đệm bên trái và vùng trống ở hàng thông tin cũng đọc từ.
            origin.withOffset(CGVector(dx: title.frame.minX - 8, dy: title.frame.midY)).tap()
            origin.withOffset(CGVector(dx: close.frame.midX, dy: ipa.frame.midY)).tap()
            XCTAssertEqual(title.label, "lay off")
            close.tap()
            XCTAssertTrue(card.waitForExistence(timeout: 3))
            XCTAssertFalse(title.exists)
            card.tap()
            XCTAssertTrue(title.waitForExistence(timeout: 3))
            let definitionAudio = app.buttons["vocabulary-english-definition"]
            XCTAssertTrue(definitionAudio.isHittable)
            definitionAudio.tap()
            XCTAssertEqual(title.label, "lay off")
            let translation = app.staticTexts["vocabulary-definition-translation"]
            XCTAssertTrue(translation.isHittable)
            XCTAssertGreaterThan(translation.frame.minY, app.buttons["vocabulary-english-definition"].frame.minY)
            XCTAssertFalse(app.buttons["vocabulary-definition-translation-toggle"].exists)
            XCTAssertFalse(app.buttons["vocabulary-example-audio"].exists)
            XCTAssertFalse(app.buttons["Từ trước"].exists)
            XCTAssertFalse(app.buttons["Từ tiếp theo"].exists)
            let learning = app.buttons["vocabulary-learning-action"]
            let hint = app.staticTexts["vocabularyPreviewPosition"]
            XCTAssertTrue(learning.isHittable)
            XCTAssertTrue(hint.isHittable)
            XCTAssertLessThan(abs(hint.frame.midX - app.frame.midX), 2)
            XCTAssertLessThanOrEqual(hint.frame.maxY - learning.frame.minY, 90)
            XCTAssertEqual(hint.label, "Vuốt trái hoặc phải để chuyển từ - Từ 2 trên 2")
            capture(app, name: "word-muted-top-\(mode)")

            let content = app.scrollViews["vocabularyPreviewContent"]
            XCTAssertFalse(app.staticTexts["Ví dụ"].exists)
            let exampleAudio = app.buttons["vocabulary-english-example"]
            scrollTo(exampleAudio, in: content)
            exampleAudio.tap()
            XCTAssertEqual(title.label, "lay off")
            scrollTo(app.staticTexts["lay sb off"], in: content)
            capture(app, name: "word-muted-usage-\(mode)")
            scrollTo(app.staticTexts["employers lay off workers"], in: content)
            let first = app.staticTexts["employers lay off workers"]
            let second = app.staticTexts["laid off hundreds of employees"]
            scrollTo(second, in: content)
            XCTAssertGreaterThan(second.frame.minY, first.frame.minY)
            scrollTo(app.staticTexts["take on"], in: content)
            XCTAssertTrue(app.staticTexts["Từ đồng nghĩa"].exists)
            XCTAssertTrue(app.staticTexts["Từ trái nghĩa"].exists)
            capture(app, name: "word-muted-related-\(mode)")
            swipe(content, next: false)
            XCTAssertEqual(title.label, "apple")
            XCTAssertTrue(app.staticTexts["Quả táo"].waitForExistence(timeout: 3))
            XCTAssertFalse(translation.exists)
            XCTAssertFalse(app.staticTexts["Công thức"].exists)
            XCTAssertEqual(hint.label, "Vuốt trái hoặc phải để chuyển từ - Từ 1 trên 2")
            XCTAssertTrue(app.buttons["Đưa từ này vào học"].isHittable)
            capture(app, name: "word-muted-minimal-\(mode)")
            swipe(content, next: false)
            XCTAssertEqual(title.label, "apple")
            swipe(content, next: true)
            XCTAssertEqual(title.label, "lay off")
            XCTAssertTrue(translation.isHittable)
            close.tap()
            XCTAssertTrue(card.waitForExistence(timeout: 3))
            app.terminate()
        }
    }

    @MainActor
    private func swipe(_ content: XCUIElement, next: Bool) {
        let start = content.coordinate(withNormalizedOffset: CGVector(dx: next ? 0.82 : 0.18, dy: 0.5))
        let end = content.coordinate(withNormalizedOffset: CGVector(dx: next ? 0.18 : 0.82, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    @MainActor
    private func scrollTo(_ element: XCUIElement, in content: XCUIElement) {
        for _ in 0..<18 {
            if element.exists, element.isHittable,
               element.frame.minY >= content.frame.minY,
               element.frame.maxY <= content.frame.maxY { return }
            let moveDown = element.exists && element.frame.midY < content.frame.midY
            let start = content.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            let end = content.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: moveDown ? 0.75 : 0.25))
            start.press(forDuration: 0.01, thenDragTo: end, withVelocity: 200, thenHoldForDuration: 0.15)
        }
        let hierarchy = XCTAttachment(string: XCUIApplication().debugDescription)
        hierarchy.name = "Nội dung sau khi cuộn"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        XCTFail("Không đưa được nội dung vào trọn vùng cuộn của thẻ.")
    }

    @MainActor
    private func capture(_ app: XCUIApplication, name: String) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name
        image.lifetime = .keepAlways
        add(image)
    }
}
