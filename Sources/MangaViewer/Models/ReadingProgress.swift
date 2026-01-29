import Foundation
import SwiftData

@Model
final class ReadingProgress {
    var id: UUID
    var currentPage: Int
    var updatedAt: Date
    var isCompleted: Bool

    var book: Book?

    init(currentPage: Int = 0) {
        self.id = UUID()
        self.currentPage = currentPage
        self.updatedAt = Date()
        self.isCompleted = false
    }
}
