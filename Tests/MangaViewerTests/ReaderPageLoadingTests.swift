import CoreGraphics
import Foundation
import Testing
@testable import MangaViewer

/// In-memory provider: pages listed in `failingPages` throw, others return a solid image of `pageSize`.
final class StubPageProvider: PageProvider, @unchecked Sendable {
    let pageCount: Int
    private let pageSize: (width: Int, height: Int)
    private let failingPages: Set<Int>

    init(pageCount: Int, pageSize: (width: Int, height: Int) = (60, 90), failingPages: Set<Int> = []) {
        self.pageCount = pageCount
        self.pageSize = pageSize
        self.failingPages = failingPages
    }

    func image(at index: Int) async throws -> PlatformImage {
        if failingPages.contains(index) {
            throw MangaViewerError.invalidImageData
        }
        return TestImages.solid(width: pageSize.width, height: pageSize.height)
    }

    func close() {}
}

@Suite("Reader page loading Tests")
@MainActor
struct ReaderPageLoadingTests {
    @Test("a page whose error placeholder cannot be rendered shows the error as text")
    func unrenderablePlaceholderShowsErrorText() async {
        let vm = makeIsolatedReader()
        vm.renderPlaceholder = { _ in nil }

        await vm.openProvider(StubPageProvider(pageCount: 2, failingPages: [0]), title: "Book")

        #expect(vm.errorMessage?.hasPrefix("Page 1:") == true)
    }

    @Test("moving to a page that loads clears the error left by a failed page")
    func pageErrorClearsOnNextLoad() async throws {
        let vm = makeIsolatedReader()
        vm.renderPlaceholder = { _ in nil }
        await vm.openProvider(StubPageProvider(pageCount: 4, failingPages: [0]), title: "Book")
        #expect(vm.errorMessage != nil)

        // The failed page left an empty image in the spread; pages 2 and 3 both have a size
        let pageSize = CGSize(width: 60, height: 90)
        func showsPagesTwoAndThree() -> Bool {
            vm.spreadImages.left?.size == pageSize && vm.spreadImages.right?.size == pageSize
        }
        #expect(!showsPagesTwoAndThree())

        vm.goToPage(2)
        for _ in 0 ..< 50 where !showsPagesTwoAndThree() {
            try await Task.sleep(for: .milliseconds(20))
        }

        #expect(showsPagesTwoAndThree())
        #expect(vm.errorMessage == nil)
    }

    @Test("a page that fails to decode is replaced by an 800x1200 placeholder")
    func failingPageShowsPlaceholder() async {
        let vm = makeIsolatedReader()
        await vm.openProvider(StubPageProvider(pageCount: 1, failingPages: [0]), title: "Broken")

        let shown = vm.spreadImages.left ?? vm.spreadImages.right
        #expect(shown?.pixelSize == CGSize(width: 800, height: 1200))
        #expect(vm.errorMessage == nil)
    }

    @Test("two portrait pages are shown as a right-to-left spread")
    func portraitPagesFormSpread() async {
        let vm = makeIsolatedReader()
        await vm.openProvider(StubPageProvider(pageCount: 4), title: "Book")

        #expect(vm.spreadImages.left != nil)
        #expect(vm.spreadImages.right != nil)
    }
}
