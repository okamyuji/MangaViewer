import CoreGraphics

enum ReaderAction: Equatable {
    case next
    case previous
    case toggleChrome
}

/// Touch rules for the reader. Right-to-left books advance with a tap on the left third
/// or a rightward swipe; left-to-right books mirror that.
enum ReaderGesture {
    static let swipeThreshold: CGFloat = 50

    static func tapAction(locationX: CGFloat, width: CGFloat, direction: ReadingDirection) -> ReaderAction {
        if locationX < width / 3 {
            return direction == .rightToLeft ? .next : .previous
        }
        if locationX > width * 2 / 3 {
            return direction == .rightToLeft ? .previous : .next
        }
        return .toggleChrome
    }

    static func swipeAction(
        translation: CGSize, zoomScale: CGFloat, overflowsHorizontally: Bool, direction: ReadingDirection
    ) -> ReaderAction? {
        let dx = translation.width
        guard zoomScale <= 1, !overflowsHorizontally,
              abs(dx) >= swipeThreshold, abs(dx) > abs(translation.height)
        else { return nil }
        let rightward = dx > 0
        return rightward == (direction == .rightToLeft) ? .next : .previous
    }

    /// A drag moves the page only along an axis where it overflows the reader, so fitWidth pages
    /// scroll vertically while a horizontal drag stays a page-turn swipe.
    static func panTranslation(_ translation: CGSize, contentSize: CGSize, containerSize: CGSize) -> CGSize {
        CGSize(
            width: overflows(contentSize.width, containerSize.width) ? translation.width : 0,
            height: overflows(contentSize.height, containerSize.height) ? translation.height : 0
        )
    }

    /// Keeps a centered page from being dragged past its edges, and recenters an axis that no
    /// longer overflows, e.g. after pinching back to fit.
    static func clampedOffset(_ offset: CGSize, contentSize: CGSize, containerSize: CGSize) -> CGSize {
        let limitX = max(0, (contentSize.width - containerSize.width) / 2)
        let limitY = max(0, (contentSize.height - containerSize.height) / 2)
        return CGSize(
            width: min(max(offset.width, -limitX), limitX),
            height: min(max(offset.height, -limitY), limitY)
        )
    }

    /// Half a point of slack so a fitWidth page whose width rounds to the reader's is not "wider".
    static func overflows(_ content: CGFloat, _ container: CGFloat) -> Bool {
        content > container + 0.5
    }

    /// `magnification` is the total scale since the pinch began (Apple's MagnifyGesture example
    /// applies it directly), so it multiplies the zoom captured at the start, not the live zoom.
    static func pinchScale(base: CGFloat, magnification: CGFloat) -> CGFloat {
        max(0.25, min(5.0, base * magnification))
    }

    /// Near-square readers (a Stage Manager window, or the toolbars toggling) keep the current mode,
    /// so the layout does not flip between one page and a spread on every small resize.
    static func prefersSinglePage(containerSize: CGSize, current: Bool) -> Bool {
        let hysteresis: CGFloat = 1.1
        if containerSize.height > containerSize.width * hysteresis {
            return true
        }
        if containerSize.width > containerSize.height * hysteresis {
            return false
        }
        return current
    }
}
