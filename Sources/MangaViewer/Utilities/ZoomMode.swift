import Foundation

enum ZoomMode: String, CaseIterable, Identifiable {
  case fitPage
  case fitWidth
  case fitHeight
  case actualSize
  case custom

  var id: String { rawValue }

  var label: String {
    switch self {
    case .fitPage: return "Fit Page"
    case .fitWidth: return "Fit Width"
    case .fitHeight: return "Fit Height"
    case .actualSize: return "Actual Size"
    case .custom: return "Custom"
    }
  }

  var icon: String {
    switch self {
    case .fitPage: return "arrow.up.left.and.arrow.down.right"
    case .fitWidth: return "arrow.left.and.right"
    case .fitHeight: return "arrow.up.and.down"
    case .actualSize: return "1.circle"
    case .custom: return "magnifyingglass"
    }
  }
}
