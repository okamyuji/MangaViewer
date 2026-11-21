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

    static func swipeAction(translation: CGSize, zoomScale: CGFloat, direction: ReadingDirection) -> ReaderAction? {
        let dx = translation.width
        guard zoomScale <= 1, abs(dx) >= swipeThreshold, abs(dx) > abs(translation.height) else { return nil }
        let rightward = dx > 0
        return rightward == (direction == .rightToLeft) ? .next : .previous
    }

    static func prefersSinglePage(containerSize: CGSize) -> Bool {
        containerSize.height > containerSize.width
    }
}
