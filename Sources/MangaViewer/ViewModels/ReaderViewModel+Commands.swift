import Foundation

extension ReaderViewModel {
    /// `.close` is handled by the view, which owns dismissal.
    func perform(_ command: ReaderCommand) {
        switch command {
        case .left:
            turnTowardLeft()
        case .right:
            turnTowardRight()
        case .next:
            nextPage()
        case .previous:
            previousPage()
        case .toggleFullScreen:
            toggleFullScreen()
        case .toggleBookmark:
            toggleBookmark()
        case .resetZoom:
            resetZoom()
        case .zoomIn:
            zoomIn()
        case .zoomOut:
            zoomOut()
        case .close:
            break
        }
    }

    private func turnTowardLeft() {
        if readingDirection == .rightToLeft {
            nextPage()
        } else {
            previousPage()
        }
    }

    private func turnTowardRight() {
        if readingDirection == .rightToLeft {
            previousPage()
        } else {
            nextPage()
        }
    }
}
