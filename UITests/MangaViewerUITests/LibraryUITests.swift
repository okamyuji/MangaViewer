import XCTest

/// Launches the iPad app into the library rather than straight into a sample book.
final class LibraryUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    func testPortraitLaunchShowsTheLibraryWithAddBooksAndSettings() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.buttons["Add Books"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Settings"].exists)
    }

    func testOpeningABookFromTheLibraryGivesTheReaderTheWholeScreen() {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = ["-UITestLibrarySample"]
        app.launch()
        let book = app.staticTexts["UITestLibrary"]
        XCTAssertTrue(book.waitForExistence(timeout: 15))
        book.tap()

        let indicator = app.staticTexts["pageIndicator"]
        XCTAssertTrue(indicator.waitForExistence(timeout: 15))
        let reader = app.otherElements["readerContent"]
        let window = app.windows.firstMatch
        let fullWidth = NSPredicate { _, _ in abs(reader.frame.width - window.frame.width) < 2 }
        wait(for: [XCTNSPredicateExpectation(predicate: fullWidth, object: nil)], timeout: 5)
        XCTAssertFalse(app.buttons["Add Books"].isHittable)

        // Right-to-left: the left side turns forward, through the spread scan on page 3
        for expected in ["3 / 6", "4 / 6", "6 / 6"] {
            reader.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)).tap()
            let turned = NSPredicate(format: "label == %@", expected)
            wait(for: [expectation(for: turned, evaluatedWith: indicator)], timeout: 5)
        }

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["Add Books"].waitForExistence(timeout: 5))
        let sidebarBack = NSPredicate { _, _ in app.buttons["Add Books"].isHittable }
        wait(for: [XCTNSPredicateExpectation(predicate: sidebarBack, object: nil)], timeout: 5)
    }
}
