import Foundation

enum SortOrder: String, CaseIterable, Identifiable {
    case title
    case dateAdded
    case lastOpened

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .title: "Title"
        case .dateAdded: "Date Added"
        case .lastOpened: "Last Opened"
        }
    }
}
