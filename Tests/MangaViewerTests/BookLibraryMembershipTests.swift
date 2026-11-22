import SwiftData
import Testing
@testable import MangaViewer

@MainActor
@Suite("Book library membership Tests")
struct BookLibraryMembershipTests {
    private let context: ModelContext

    init() throws {
        let schema = Schema([Book.self, ReadingProgress.self, Bookmark.self, Tag.self])
        let container = try ModelContainer(
            for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        context = ModelContext(container)
    }

    private func savedBook() throws -> Book {
        let book = Book(title: "Vol 1", filePath: "/s/Vol 1.cbz", type: .cbz, totalPages: 1)
        context.insert(book)
        try context.save()
        return book
    }

    @Test("a saved book is in the library")
    func savedBookIsListed() throws {
        #expect(try savedBook().isInLibrary)
    }

    @Test("a book deleted but not yet saved is out of the library")
    func deletedBeforeSaveIsNotListed() throws {
        let book = try savedBook()
        context.delete(book)
        #expect(!book.isInLibrary)
    }

    @Test("a book deleted and saved is out of the library, though SwiftData no longer marks it deleted")
    func deletedAfterSaveIsNotListed() throws {
        let book = try savedBook()
        context.delete(book)
        try context.save()
        #expect(!book.isDeleted)
        #expect(!book.isInLibrary)
    }
}
