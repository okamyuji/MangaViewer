import SwiftUI
import Testing
@testable import MangaViewer

@Suite("ReaderCommand Tests")
struct ReaderCommandTests {
    @Test(
        "macOS key codes map to reader commands",
        arguments: [
            (UInt16(123), ReaderCommand?.some(.left)),
            (124, .right),
            (49, .next),
            (3, .toggleFullScreen),
            (11, .toggleBookmark),
            (29, .resetZoom),
            (24, .zoomIn),
            (27, .zoomOut),
            (53, .close),
            (0, nil),
            (125, nil)
        ]
    )
    func macKeyCodes(code: UInt16, expected: ReaderCommand?) {
        #expect(ReaderCommand(macKeyCode: code) == expected)
    }

    @Test("hardware keyboard keys map to the same commands as on macOS")
    func keyEquivalents() {
        #expect(ReaderCommand(key: .leftArrow) == .left)
        #expect(ReaderCommand(key: .rightArrow) == .right)
        #expect(ReaderCommand(key: .space) == .next)
        #expect(ReaderCommand(key: "f") == .toggleFullScreen)
        #expect(ReaderCommand(key: "b") == .toggleBookmark)
        #expect(ReaderCommand(key: "0") == .resetZoom)
        #expect(ReaderCommand(key: "=") == .zoomIn)
        #expect(ReaderCommand(key: "-") == .zoomOut)
        #expect(ReaderCommand(key: .escape) == .close)
        #expect(ReaderCommand(key: "x") == nil)
        #expect(ReaderCommand(key: .upArrow) == nil)
    }
}

@Suite("ReaderViewModel.perform Tests")
@MainActor
struct ReaderPerformTests {
    private func openReader(direction: ReadingDirection) async -> ReaderViewModel {
        let vm = makeIsolatedReader()
        vm.setReadingDirection(direction)
        vm.setPrefersSinglePage(true)
        await vm.openProvider(StubPageProvider(pageCount: 5), title: "Book")
        vm.goToPage(2)
        return vm
    }

    @Test("arrow keys follow the reading direction")
    func arrowsFollowDirection() async {
        let rtl = await openReader(direction: .rightToLeft)
        rtl.perform(.left)
        #expect(rtl.currentPage == 3)
        rtl.perform(.right)
        #expect(rtl.currentPage == 2)

        let ltr = await openReader(direction: .leftToRight)
        ltr.perform(.left)
        #expect(ltr.currentPage == 1)
        ltr.perform(.right)
        #expect(ltr.currentPage == 2)
    }

    @Test("next and previous ignore the reading direction")
    func nextPrevious() async {
        let vm = await openReader(direction: .rightToLeft)
        vm.perform(.next)
        #expect(vm.currentPage == 3)
        vm.perform(.previous)
        #expect(vm.currentPage == 2)
    }

    @Test("zoom and full-screen commands change the view state")
    func zoomAndFullScreen() {
        let vm = makeIsolatedReader()
        vm.perform(.zoomIn)
        #expect(vm.zoomScale == 1.25)
        vm.perform(.zoomOut)
        vm.perform(.zoomOut)
        #expect(vm.zoomScale == 0.8)
        vm.perform(.resetZoom)
        #expect(vm.zoomScale == 1.0)
        #expect(vm.zoomMode == .fitPage)
        vm.perform(.toggleFullScreen)
        #expect(vm.isFullScreen)
    }

    @Test("bookmark and close commands are no-ops without an open library book")
    func bookmarkAndCloseWithoutBook() {
        let vm = makeIsolatedReader()
        vm.perform(.toggleBookmark)
        vm.perform(.close)
        #expect(vm.showBookmarkToast == false)
        #expect(vm.isFullScreen == false)
    }
}
