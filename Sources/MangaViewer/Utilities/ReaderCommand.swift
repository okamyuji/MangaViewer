import SwiftUI

/// Keyboard commands shared by the macOS key monitor and the iPad hardware keyboard.
enum ReaderCommand: Equatable {
    case left
    case right
    case next
    case previous
    case toggleFullScreen
    case toggleBookmark
    case resetZoom
    case zoomIn
    case zoomOut
    case close

    init?(macKeyCode: UInt16) {
        switch macKeyCode {
        case 123: self = .left
        case 124: self = .right
        case 49: self = .next
        case 3: self = .toggleFullScreen
        case 11: self = .toggleBookmark
        case 29: self = .resetZoom
        case 24: self = .zoomIn
        case 27: self = .zoomOut
        case 53: self = .close
        default: return nil
        }
    }

    init?(key: KeyEquivalent) {
        switch key {
        case .leftArrow: self = .left
        case .rightArrow: self = .right
        case .space: self = .next
        case "f": self = .toggleFullScreen
        case "b": self = .toggleBookmark
        case "0": self = .resetZoom
        case "=", "+": self = .zoomIn
        case "-": self = .zoomOut
        case .escape: self = .close
        default: return nil
        }
    }
}
