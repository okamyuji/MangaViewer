import Foundation

enum SortOrder: String, CaseIterable, Identifiable {
    case title
    case dateAdded
    case lastOpened

    var id: String { rawValue }

    var label: String {
        switch self {
        case .title: return "Title"
        case .dateAdded: return "Date Added"
        case .lastOpened: return "Last Opened"
        }
    }
}
