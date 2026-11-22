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

    func testSelectModeDeletesTheChosenBooksTogether() {
        let app = launchWithSeries()
        app.buttons["Select"].tap()
        app.staticTexts["Vol 2"].tap()
        app.staticTexts["Vol 10"].tap()
        XCTAssertFalse(app.staticTexts["pageIndicator"].exists)

        app.buttons["deleteSelectedBooks"].tap()
        let confirm = app.buttons.matching(
            NSPredicate(format: "label == 'Delete' AND identifier != 'deleteSelectedBooks'")
        ).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()

        let gone = NSPredicate(format: "exists == false")
        wait(for: [expectation(for: gone, evaluatedWith: app.staticTexts["Vol 2"])], timeout: 5)
        XCTAssertFalse(app.staticTexts["Vol 10"].exists)
        XCTAssertTrue(app.staticTexts["Vol 1"].exists)
    }

    func testTurningPastTheLastPageOpensTheNextVolume() {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = launchWithSeries()
        app.staticTexts["Vol 2"].tap()
        let indicator = app.staticTexts["pageIndicator"]
        XCTAssertTrue(indicator.waitForExistence(timeout: 15))
        let reader = app.otherElements["readerContent"]

        // Right-to-left: the left side turns forward. Vol 2 has 3 pages, then Vol 10 follows
        for expected in ["3 / 3", "1 / 3"] {
            reader.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)).tap()
            let turned = NSPredicate(format: "label == %@", expected)
            wait(for: [expectation(for: turned, evaluatedWith: indicator)], timeout: 5)
        }
        XCTAssertTrue(app.navigationBars["Vol 10"].waitForExistence(timeout: 5))
    }

    private func launchWithSeries() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestLibrarySeries"]
        app.launch()
        for title in ["Vol 1", "Vol 2", "Vol 10"] {
            XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 15))
        }
        return app
    }
}
