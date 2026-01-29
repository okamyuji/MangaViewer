import Foundation
import SwiftData

@Model
final class Book {
    @Attribute(.unique) var id: UUID
    var title: String
    var filePath: String
    @Attribute(.externalStorage) var thumbnailData: Data?
    var addedAt: Date
    var lastOpenedAt: Date?
    var totalPages: Int
    var typeRawValue: String

    @Relationship(deleteRule: .cascade, inverse: \ReadingProgress.book)
    var progress: ReadingProgress?

    @Relationship(deleteRule: .cascade, inverse: \Bookmark.book)
    var bookmarks: [Bookmark]

    @Relationship(inverse: \Tag.books)
    var tags: [Tag]

    var type: BookType {
        get { BookType(rawValue: typeRawValue) ?? .folder }
        set { typeRawValue = newValue.rawValue }
    }

    init(title: String, filePath: String, type: BookType, totalPages: Int) {
        self.id = UUID()
        self.title = title
        self.filePath = filePath
        self.typeRawValue = type.rawValue
        self.totalPages = totalPages
        self.addedAt = Date()
        self.bookmarks = []
        self.tags = []
    }
}
