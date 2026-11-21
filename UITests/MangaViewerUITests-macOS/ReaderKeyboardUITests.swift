import XCTest

/// Drives the macOS reader with a generated 4-page right-to-left sample book.
final class ReaderKeyboardUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testArrowKeysTurnPagesInReadingDirection() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestSampleBook"]
        app.launch()
        let indicator = app.staticTexts["pageIndicator"]
        XCTAssertTrue(indicator.waitForExistence(timeout: 15))
        XCTAssertEqual(indicator.value as? String ?? indicator.label, "1 / 4")

        // Right-to-left: the left arrow moves forward a spread, the right arrow back
        press(.leftArrow, in: app, until: "3 / 4", on: indicator)
        press(.rightArrow, in: app, until: "1 / 4", on: indicator)
        app.terminate()
    }

    /// Keys sent before the reader has loaded are dropped, so retry until the page changes.
    private func press(_ key: XCUIKeyboardKey, in app: XCUIApplication, until page: String, on indicator: XCUIElement) {
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            app.typeKey(key, modifierFlags: [])
            let changed = NSPredicate { _, _ in (indicator.value as? String ?? indicator.label) == page }
            let expectation = XCTNSPredicateExpectation(predicate: changed, object: nil)
            if XCTWaiter.wait(for: [expectation], timeout: 2) == .completed {
                return
            }
        }
        XCTFail("page indicator stayed at \(indicator.value as? String ?? indicator.label), expected \(page)")
    }
}
