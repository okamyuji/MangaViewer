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
}
