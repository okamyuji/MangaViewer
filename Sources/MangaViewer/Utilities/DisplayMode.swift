import Foundation

enum DisplayMode: String, CaseIterable, Identifiable {
    case single
    case spread

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .single: return "Single Page"
        case .spread: return "Spread (2 Pages)"
        }
    }

    var icon: String {
        switch self {
        case .single: return "doc"
        case .spread: return "doc.on.doc"
        }
    }
}
