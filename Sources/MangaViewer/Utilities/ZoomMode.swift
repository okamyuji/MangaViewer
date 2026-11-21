import Foundation

enum ZoomMode: String, CaseIterable, Identifiable {
    case fitPage
    case fitWidth
    case fitHeight
    case actualSize
    case custom

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .fitPage: "Fit Page"
        case .fitWidth: "Fit Width"
        case .fitHeight: "Fit Height"
        case .actualSize: "Actual Size"
        case .custom: "Custom"
        }
    }

    var icon: String {
        switch self {
        case .fitPage: "arrow.up.left.and.arrow.down.right"
        case .fitWidth: "arrow.left.and.right"
        case .fitHeight: "arrow.up.and.down"
        case .actualSize: "1.circle"
        case .custom: "magnifyingglass"
        }
    }
}
