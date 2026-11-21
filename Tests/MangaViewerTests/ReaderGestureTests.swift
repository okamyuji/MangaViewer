import CoreGraphics
import Testing
@testable import MangaViewer

@Suite("ReaderGesture Tests")
struct ReaderGestureTests {
    @Test(
        "tap zones map to page turns by reading direction",
        arguments: [
            (CGFloat(0), ReadingDirection.rightToLeft, ReaderAction.next),
            (299, .rightToLeft, .next),
            (300, .rightToLeft, .toggleChrome),
            (450, .rightToLeft, .toggleChrome),
            (600, .rightToLeft, .toggleChrome),
            (601, .rightToLeft, .previous),
            (900, .rightToLeft, .previous),
            (10, .leftToRight, .previous),
            (450, .leftToRight, .toggleChrome),
            (890, .leftToRight, .next)
        ]
    )
    func tapZones(locationX: CGFloat, direction: ReadingDirection, expected: ReaderAction) {
        #expect(ReaderGesture.tapAction(locationX: locationX, width: 900, direction: direction) == expected)
    }

    @Test(
        "horizontal swipes turn pages by reading direction",
        arguments: [
            (CGFloat(80), CGFloat(0), ReadingDirection.rightToLeft, ReaderAction?.some(.next)),
            (-80, 0, .rightToLeft, .previous),
            (80, 0, .leftToRight, .previous),
            (-80, 0, .leftToRight, .next),
            (50, 0, .rightToLeft, .next),
            (49, 0, .rightToLeft, nil),
            (-49, 0, .leftToRight, nil),
            (80, 80, .rightToLeft, nil),
            (80, -120, .leftToRight, nil)
        ]
    )
    func swipes(dx: CGFloat, dy: CGFloat, direction: ReadingDirection, expected: ReaderAction?) {
        let action = ReaderGesture.swipeAction(
            translation: CGSize(width: dx, height: dy), zoomScale: 1, overflowsHorizontally: false,
            direction: direction
        )
        #expect(action == expected)
    }

    @Test("dragging a zoomed-in page pans instead of turning the page")
    func zoomedDragDoesNotTurn() {
        let translation = CGSize(width: 300, height: 0)
        #expect(ReaderGesture.swipeAction(
            translation: translation, zoomScale: 1.01, overflowsHorizontally: false, direction: .rightToLeft
        ) == nil)
        #expect(ReaderGesture.swipeAction(
            translation: translation, zoomScale: 0.8, overflowsHorizontally: false, direction: .rightToLeft
        ) == .next)
    }

    @Test("dragging a page wider than the reader pans instead of turning the page")
    func overflowingDragDoesNotTurn() {
        #expect(ReaderGesture.swipeAction(
            translation: CGSize(width: 300, height: 0), zoomScale: 1, overflowsHorizontally: true,
            direction: .rightToLeft
        ) == nil)
    }

    @Test(
        "a drag pans only along the axes where the page overflows the reader",
        arguments: [
            // fitWidth portrait page on a portrait iPad: taller than the reader
            (CGSize(width: 834, height: 1251), CGSize(width: 0, height: -40)),
            // wider than the reader, e.g. actualSize of a wide scan
            (CGSize(width: 1200, height: 800), CGSize(width: 30, height: 0)),
            (CGSize(width: 1200, height: 1251), CGSize(width: 30, height: -40)),
            // fits inside the reader
            (CGSize(width: 834, height: 1100), CGSize.zero),
            (CGSize(width: 700, height: 1000), CGSize.zero)
        ]
    )
    func panOnlyOverflowingAxes(contentSize: CGSize, expected: CGSize) {
        let pan = ReaderGesture.panTranslation(
            CGSize(width: 30, height: -40), contentSize: contentSize,
            containerSize: CGSize(width: 834, height: 1100)
        )
        #expect(pan == expected)
    }

    @Test(
        "a page offset stays within the part of the page that overflows the reader",
        arguments: [
            // 1251 tall in a 1100 reader: at most 75.5 up or down, no horizontal travel
            (CGSize(width: 834, height: 1251), CGSize(width: 40, height: -200), CGSize(width: 0, height: -75.5)),
            // after pinching back to fit, a pan left over from the zoom returns to center
            (CGSize(width: 700, height: 1000), CGSize(width: 30, height: 30), CGSize.zero),
            (CGSize(width: 1200, height: 1251), CGSize(width: 100, height: 10), CGSize(width: 100, height: 10)),
            // past the positive edges of both axes: 183 right, 75.5 down at most
            (CGSize(width: 1200, height: 1251), CGSize(width: 500, height: 300), CGSize(width: 183, height: 75.5)),
            (CGSize(width: 1200, height: 1251), CGSize(width: -500, height: -300), CGSize(width: -183, height: -75.5)),
            // exactly at the edge stays put
            (CGSize(width: 1200, height: 1251), CGSize(width: 183, height: -75.5), CGSize(width: 183, height: -75.5))
        ]
    )
    func clampedOffset(contentSize: CGSize, offset: CGSize, expected: CGSize) {
        let clamped = ReaderGesture.clampedOffset(
            offset, contentSize: contentSize, containerSize: CGSize(width: 834, height: 1100)
        )
        #expect(clamped == expected)
    }

    @Test(
        "a pinch scales the zoom from where the gesture started, within 0.25 to 5",
        arguments: [
            (CGFloat(1), CGFloat(1.5), CGFloat(1.5)),
            (2, 1.5, 3),
            (2, 0.5, 1),
            (4, 2, 5),
            (0.5, 0.25, 0.25)
        ]
    )
    func pinchScale(base: CGFloat, magnification: CGFloat, expected: CGFloat) {
        #expect(ReaderGesture.pinchScale(base: base, magnification: magnification) == expected)
    }

    @Test("portrait containers show one page, landscape and square show a spread")
    func singlePageByOrientation() {
        #expect(ReaderGesture.prefersSinglePage(containerSize: CGSize(width: 834, height: 1194)))
        #expect(!ReaderGesture.prefersSinglePage(containerSize: CGSize(width: 1194, height: 834)))
        #expect(!ReaderGesture.prefersSinglePage(containerSize: CGSize(width: 800, height: 800)))
        #expect(!ReaderGesture.prefersSinglePage(containerSize: .zero))
    }
}

@Suite("Reader single-page mode Tests")
@MainActor
struct ReaderSinglePageTests {
    @Test("single-page mode shows one portrait page and steps one page at a time")
    func singlePageSteps() async {
        let vm = makeIsolatedReader()
        vm.setPrefersSinglePage(true)
        await vm.openProvider(StubPageProvider(pageCount: 4), title: "Book")

        #expect((vm.spreadImages.left == nil) != (vm.spreadImages.right == nil))
        vm.nextPage()
        #expect(vm.currentPage == 1)
    }

    @Test("leaving single-page mode returns to two-page spreads")
    func backToSpread() async {
        let vm = makeIsolatedReader()
        vm.setPrefersSinglePage(true)
        await vm.openProvider(StubPageProvider(pageCount: 4), title: "Book")
        vm.setPrefersSinglePage(false)
        for _ in 0 ..< 100 where vm.spreadImages.left == nil || vm.spreadImages.right == nil {
            try? await Task.sleep(for: .milliseconds(20))
        }

        #expect(vm.spreadImages.left != nil)
        #expect(vm.spreadImages.right != nil)
        vm.nextPage()
        #expect(vm.currentPage == 2)
    }
}
