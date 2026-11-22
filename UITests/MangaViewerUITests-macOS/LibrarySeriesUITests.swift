import XCTest

/// Drives the macOS library with three volumes of one series: Vol 1, Vol 2 and Vol 10.
final class LibrarySeriesUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITestLibrarySeries"]
        app.launch()
        // Books appear one by one as the folder is scanned, which moves rows under a click
        for title in ["Vol 1", "Vol 2", "Vol 10"] {
            XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 15))
        }
    }

    override func tearDownWithError() throws {
        app.terminate()
    }

    func testTitlesAreListedInNaturalNumberOrder() {
        let positions = ["Vol 1", "Vol 2", "Vol 10"].map { app.staticTexts[$0].frame.minY }
        XCTAssertEqual(positions, positions.sorted())
    }

    func testCommandClickedBooksAreDeletedTogetherFromTheContextMenu() {
        app.staticTexts["Vol 2"].click()
        commandClick(app.staticTexts["Vol 10"])
        assertSelected(["Vol 2", "Vol 10"])
        app.outlines.staticTexts["Vol 10"].rightClick()
        app.menuItems["Delete 2 Books"].click()
        confirmDeletion()

        XCTAssertTrue(waitForDisappearance(of: app.staticTexts["Vol 2"]))
        XCTAssertFalse(app.staticTexts["Vol 10"].exists)
        XCTAssertTrue(app.staticTexts["Vol 1"].exists)
    }

    func testRightClickingABookOutsideTheSelectionDeletesOnlyThatBook() {
        app.staticTexts["Vol 1"].click()
        commandClick(app.staticTexts["Vol 2"])
        assertSelected(["Vol 1", "Vol 2"])
        app.outlines.staticTexts["Vol 10"].rightClick()
        app.menuItems["Delete Book"].click()
        confirmDeletion()

        XCTAssertTrue(waitForDisappearance(of: app.staticTexts["Vol 10"]))
        XCTAssertTrue(app.staticTexts["Vol 1"].exists)
        XCTAssertTrue(app.staticTexts["Vol 2"].exists)
    }

    func testTurningPastTheLastPageOpensTheNextVolumeInNaturalOrder() {
        app.staticTexts["Vol 2"].click()
        let indicator = app.staticTexts["pageIndicator"]
        XCTAssertTrue(indicator.waitForExistence(timeout: 15))

        // Right-to-left: the left arrow moves forward. Vol 2 has 3 pages, so pages 1-2 then 3, then Vol 10
        press(.leftArrow, until: "3 / 3", on: indicator)
        press(.leftArrow, until: "1 / 3", on: indicator)
        let titled = NSPredicate { _, _ in self.app.windows.firstMatch.title.contains("Vol 10") }
        wait(for: [XCTNSPredicateExpectation(predicate: titled, object: nil)], timeout: 5)
    }

    func testATagIsStillDeletedFromItsOwnContextMenu() {
        app.buttons["Add Tag"].click()
        let name = app.textFields["Tag Name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.click()
        name.typeText("Manga")
        app.buttons["Add"].click()

        let tag = app.outlines.descendants(matching: .any)["Manga"].firstMatch
        XCTAssertTrue(tag.waitForExistence(timeout: 5))
        tag.rightClick()
        // The menu bar's Edit menu has a Delete item too; the context menu belongs to the window
        app.windows.firstMatch.menuItems["Delete"].click()

        XCTAssertTrue(waitForDisappearance(of: tag))
        XCTAssertTrue(app.staticTexts["Vol 1"].exists)
    }

    private func commandClick(_ element: XCUIElement) {
        // XCTest runs tests on the main thread; the modifier API needs that isolation spelled out
        MainActor.assumeIsolated {
            XCUIElement.perform(withKeyModifiers: .command) {
                element.click()
            }
        }
    }

    private func assertSelected(_ titles: [String]) {
        for title in titles {
            let row = app.outlines.cells.containing(.staticText, identifier: title).firstMatch
            let selected = NSPredicate(format: "isSelected == true")
            XCTAssertEqual(
                XCTWaiter.wait(for: [expectation(for: selected, evaluatedWith: row)], timeout: 5), .completed,
                "\(title) is not selected"
            )
        }
    }

    private func confirmDeletion() {
        let confirm = app.sheets.buttons["Delete"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.click()
    }

    private func waitForDisappearance(of element: XCUIElement) -> Bool {
        let gone = NSPredicate(format: "exists == false")
        return XCTWaiter.wait(for: [expectation(for: gone, evaluatedWith: element)], timeout: 5) == .completed
    }

    /// Keys sent before the reader has loaded are dropped, so retry until the page changes.
    private func press(_ key: XCUIKeyboardKey, until page: String, on indicator: XCUIElement) {
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            app.typeKey(key, modifierFlags: [])
            let changed = NSPredicate { _, _ in (indicator.value as? String ?? indicator.label) == page }
            if XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: changed, object: nil)], timeout: 2)
                == .completed {
                return
            }
        }
        XCTFail("page indicator stayed at \(indicator.value as? String ?? indicator.label), expected \(page)")
    }
}
