import XCTest

/// Drives the reader on an iPad simulator with a generated 4-page right-to-left sample book.
final class ReaderTouchUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = ["-UITestSampleBook"]
        app.launch()
        XCTAssertTrue(pageIndicator.waitForExistence(timeout: 15))
        XCTAssertEqual(pageIndicator.label, "1 / 4")
    }

    private var pageIndicator: XCUIElement {
        app.staticTexts["pageIndicator"]
    }

    private var readerContent: XCUIElement {
        app.otherElements["readerContent"]
    }

    private func tap(atX fraction: CGFloat) {
        readerContent.coordinate(withNormalizedOffset: CGVector(dx: fraction, dy: 0.5)).tap()
    }

    private func waitForPage(_ label: String) {
        let predicate = NSPredicate(format: "label == %@", label)
        let found = expectation(for: predicate, evaluatedWith: pageIndicator)
        wait(for: [found], timeout: 5)
    }

    func testLeftTapAdvancesAndRightTapGoesBackInRightToLeftBook() {
        tap(atX: 0.15)
        waitForPage("2 / 4")
        tap(atX: 0.85)
        waitForPage("1 / 4")
    }

    func testSwipeRightAdvancesAndSwipeLeftGoesBackInRightToLeftBook() {
        readerContent.swipeRight()
        waitForPage("2 / 4")
        readerContent.swipeLeft()
        waitForPage("1 / 4")
    }

    func testCenterTapTogglesReaderToolbar() {
        XCTAssertTrue(app.otherElements["readerToolbar"].exists)
        tap(atX: 0.5)
        XCTAssertTrue(app.otherElements["readerToolbar"].waitForNonExistence(timeout: 5))
        tap(atX: 0.5)
        XCTAssertTrue(app.otherElements["readerToolbar"].waitForExistence(timeout: 5))
    }

    func testPannedPageIsPulledBackWhenTheReaderGetsShorter() {
        // Full screen, zoomed in: drag the page down until its top edge reaches the reader's top
        tap(atX: 0.5)
        XCTAssertTrue(app.otherElements["readerToolbar"].waitForNonExistence(timeout: 5))
        readerContent.pinch(withScale: 2, velocity: 1)
        let page = app.images["pageImage"].firstMatch
        for _ in 0 ..< 4 {
            readerContent.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
                .press(
                    forDuration: 0.1,
                    thenDragTo: readerContent.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95))
                )
        }
        XCTAssertEqual(
            page.frame.minY, readerContent.frame.minY, accuracy: 2,
            "page \(page.frame) did not reach the top of the reader \(readerContent.frame)"
        )

        // Showing the toolbars makes the reader shorter, so the page may move less;
        // without pulling it back its top edge would leave a gap
        tap(atX: 0.5)
        XCTAssertTrue(app.otherElements["readerToolbar"].waitForExistence(timeout: 5))
        // Give the toolbar animation and the relayout time to finish
        let deadline = Date().addingTimeInterval(10)
        while page.frame.minY > readerContent.frame.minY + 2, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTAssertLessThanOrEqual(
            page.frame.minY, readerContent.frame.minY + 2,
            "page \(page.frame) was not pulled back into the reader \(readerContent.frame)"
        )
    }

    func testLandscapeSpreadKeepsTheTitleOutOfTheReadingArea() {
        XCUIDevice.shared.orientation = .landscapeLeft
        let window = app.windows.firstMatch
        let settled = NSPredicate { _, _ in self.readerContent.frame.width > self.readerContent.frame.height }
        wait(for: [XCTNSPredicateExpectation(predicate: settled, object: nil)], timeout: 10)

        // A large title adds a whole row above the pages; the inline title sits in the bar
        XCTAssertLessThan(
            readerContent.frame.minY - window.frame.minY, 90,
            "reader \(readerContent.frame) starts too far below the top of \(window.frame)"
        )

        // Full screen hides every bar, so the pages start at the top of the screen
        tap(atX: 0.5)
        let fullScreen = NSPredicate { _, _ in self.readerContent.frame.minY - window.frame.minY < 1 }
        wait(for: [XCTNSPredicateExpectation(predicate: fullScreen, object: nil)], timeout: 5)
    }

    func testPinchZoomsAndAZoomedDragPansInsteadOfTurningThePage() {
        let page = app.images["pageImage"].firstMatch
        XCTAssertTrue(page.waitForExistence(timeout: 5))
        let fitWidth = page.frame.width

        readerContent.pinch(withScale: 2, velocity: 1)
        let zoomed = NSPredicate { _, _ in page.frame.width > fitWidth * 1.5 }
        wait(for: [XCTNSPredicateExpectation(predicate: zoomed, object: nil)], timeout: 5)

        let before = page.frame
        readerContent.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5))
            .press(
                forDuration: 0.1,
                thenDragTo: readerContent.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5))
            )
        XCTAssertEqual(pageIndicator.label, "1 / 4")
        XCTAssertGreaterThan(page.frame.minX, before.minX, "a zoomed drag should move the page \(page.frame)")
    }

    func testPortraitShowsOnePagePerStep() {
        tap(atX: 0.15)
        waitForPage("2 / 4")
        tap(atX: 0.15)
        waitForPage("3 / 4")
    }
}
