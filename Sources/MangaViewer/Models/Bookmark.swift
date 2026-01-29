import Foundation
import SwiftData

@Model
final class Bookmark {
    var id: UUID
    var pageNumber: Int
    var note: String?
    var createdAt: Date

    var book: Book?

    init(pageNumber: Int, note: String? = nil) {
        id = UUID()
        self.pageNumber = pageNumber
        self.note = note
        createdAt = Date()
    }
}
