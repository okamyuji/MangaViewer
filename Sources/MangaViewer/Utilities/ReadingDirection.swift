import Foundation

enum ReadingDirection: String, CaseIterable, Identifiable {
    case leftToRight
    case rightToLeft

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .leftToRight: "Left to Right"
        case .rightToLeft: "Right to Left (Manga)"
        }
    }

    var icon: String {
        switch self {
        case .leftToRight: "arrow.right"
        case .rightToLeft: "arrow.left"
        }
    }
}
