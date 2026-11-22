import Foundation
import SwiftData
import Testing
@testable import MangaViewer

private func book(_ path: String, type: BookType = .cbz) -> Book {
    Book(title: (path as NSString).lastPathComponent, filePath: path, type: type, totalPages: 1)
}

@Suite("Next volume Tests")
struct NextVolumeSelectionTests {
    @Test("picks the next file name in natural order, so 9 is followed by 10")
    func naturalOrder() {
        let vol1 = book("/s/Vol 1.cbz")
        let vol2 = book("/s/Vol 2.cbz")
        let vol9 = book("/s/Vol 9.cbz")
        let vol10 = book("/s/Vol 10.cbz")
        let library = [vol10, vol2, vol1, vol9]

        #expect(Book.nextVolume(after: vol1, in: library) === vol2)
        #expect(Book.nextVolume(after: vol2, in: library) === vol9)
        #expect(Book.nextVolume(after: vol9, in: library) === vol10)
    }

    @Test("returns nil for the last volume")
    func lastVolume() {
        let library = ["/s/a1.zip", "/s/a2.zip"].map { book($0) }
        #expect(Book.nextVolume(after: library[1], in: library) == nil)
    }

    @Test("ignores books in other folders, even when their names come next")
    func otherFolders() {
        let current = book("/s/Vol 1.cbz")
        let elsewhere = book("/t/Vol 2.cbz")
        let nested = book("/s/sub/Vol 2.cbz")
        #expect(Book.nextVolume(after: current, in: [current, elsewhere, nested]) == nil)
    }

    @Test("returns nil when the current book is the only one in the library")
    func alone() {
        let current = book("/s/Vol 1.cbz")
        #expect(Book.nextVolume(after: current, in: [current]) == nil)
    }

    @Test("orders folder books and archives by name together")
    func mixedTypes() {
        let first = book("/s/Vol 1", type: .folder)
        let second = book("/s/Vol 2.rar", type: .cbr)
        let third = book("/s/Vol 3.zip")
        #expect(Book.nextVolume(after: first, in: [third, second, first]) === second)
        #expect(Book.nextVolume(after: second, in: [third, second, first]) === third)
    }
}

@MainActor
@Suite("Reader next volume Tests", .serialized)
struct ReaderNextVolumeTests {
    private let context: ModelContext
    private let first: Book
    private let second: Book

    init() throws {
        let schema = Schema([Book.self, ReadingProgress.self, Bookmark.self, Tag.self])
        let container = try ModelContainer(
            for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        context = ModelContext(container)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let firstURL = folder.appendingPathComponent("Vol 9.cbz")
        let secondURL = folder.appendingPathComponent("Vol 10.cbz")
        try SampleBook.writeCBZ(to: firstURL, pageCount: 4)
        try SampleBook.writeCBZ(to: secondURL, pageCount: 3)
        first = Book(title: "Vol 9", filePath: firstURL.path, type: .cbz, totalPages: 4)
        second = Book(title: "Vol 10", filePath: secondURL.path, type: .cbz, totalPages: 3)
        context.insert(first)
        context.insert(second)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0 ..< 100 where !condition() {
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    @Test("next page on the last page opens the next volume from its first page")
    func lastPageOpensNextVolume() async throws {
        let progress = ReadingProgress()
        progress.currentPage = 2
        second.progress = progress
        let reader = makeIsolatedReader()
        await reader.openBook(first, modelContext: context, startPage: 3)
        #expect(reader.canGoForward)

        reader.nextPage()
        try await waitUntil { reader.currentBook === second && !reader.isLoading }

        #expect(reader.currentBook === second)
        #expect(reader.currentPage == 0)
        #expect(reader.totalPages == 3)
        #expect(first.progress?.currentPage == 3)
        #expect(first.progress?.isCompleted == true)
        reader.closeBook()
    }

    @Test("next page on the last two-page spread opens the next volume")
    func lastSpreadOpensNextVolume() async throws {
        let reader = makeIsolatedReader()
        await reader.openBook(first, modelContext: context, startPage: 2)

        reader.nextPage()
        try await waitUntil { reader.currentBook === second && !reader.isLoading }

        #expect(reader.currentBook === second)
        #expect(reader.currentPage == 0)
        reader.closeBook()
    }

    @Test("a volume opened with progress starts at that page unless a start page is given")
    func savedProgressIsKeptWithoutStartPage() async {
        let progress = ReadingProgress()
        progress.currentPage = 2
        second.progress = progress
        let reader = makeIsolatedReader()

        await reader.openBook(second, modelContext: context)

        #expect(reader.currentPage == 2)
        reader.closeBook()
    }

    @Test("next page on the last spread of the last volume moves to its last page")
    func lastSpreadOfLastVolumeMovesToLastPage() async throws {
        let reader = makeIsolatedReader()
        await reader.openBook(second, modelContext: context, startPage: 1)

        reader.nextPage()
        try await waitUntil { reader.currentPage == 2 && !reader.isLoading }

        #expect(reader.currentBook === second)
        #expect(reader.currentPage == 2)
        reader.closeBook()
    }

    @Test("next page on the last page of the last volume stays on that page")
    func lastVolumeStays() async throws {
        let reader = makeIsolatedReader()
        await reader.openBook(second, modelContext: context, startPage: 2)
        #expect(reader.nextVolume == nil)
        #expect(!reader.canGoForward)

        reader.nextPage()
        try await Task.sleep(for: .milliseconds(200))

        #expect(reader.currentBook === second)
        #expect(reader.currentPage == 2)
        reader.closeBook()
    }

    @Test("a next volume deleted from the library while reading is not opened")
    func deletedNextVolumeStays() async throws {
        let reader = makeIsolatedReader()
        await reader.openBook(first, modelContext: context, startPage: 3)
        context.delete(second)
        try context.save()

        reader.nextPage()
        try await Task.sleep(for: .milliseconds(200))

        #expect(reader.currentBook === first)
        #expect(reader.currentPage == 3)
        #expect(reader.nextVolume == nil)
        reader.closeBook()
    }

    @Test("a page turn while the next volume opens does not move that volume past its first page")
    func pageTurnDuringVolumeOpenIsIgnored() async throws {
        let reader = makeIsolatedReader()
        await reader.openBook(first, modelContext: context, startPage: 3)

        reader.nextPage()
        var turnedWhileOpening = false
        for _ in 0 ..< 10000 where !turnedWhileOpening {
            if reader.currentBook === second, reader.isLoading {
                reader.nextPage()
                turnedWhileOpening = true
            }
            await Task.yield()
        }
        try #require(turnedWhileOpening)
        try await waitUntil { !reader.isLoading && reader.totalPages == 3 }

        #expect(reader.currentPage == 0)
        reader.closeBook()
    }

    @Test("closing the reader while a volume opens does not mark that volume completed")
    func closeDuringOpenKeepsProgress() async throws {
        let reader = makeIsolatedReader()
        await reader.openBook(first, modelContext: context, startPage: 3)

        reader.nextPage()
        for _ in 0 ..< 10000 where reader.currentBook !== second {
            await Task.yield()
        }
        try #require(reader.currentBook === second)
        reader.closeBook()

        #expect(second.progress?.isCompleted != true)
    }

    @Test("a volume imported while reading becomes the next volume by the last page")
    func importedVolumeIsFoundAtTheEnd() async throws {
        let reader = makeIsolatedReader()
        await reader.openBook(second, modelContext: context, startPage: 0)
        #expect(reader.nextVolume == nil)
        let folder = URL(fileURLWithPath: second.filePath).deletingLastPathComponent()
        let laterURL = folder.appendingPathComponent("Vol 11.cbz")
        try SampleBook.writeCBZ(to: laterURL, pageCount: 2)
        let later = Book(title: "Vol 11", filePath: laterURL.path, type: .cbz, totalPages: 2)
        context.insert(later)

        reader.goToPage(2)
        try await waitUntil { reader.nextVolume != nil }

        #expect(reader.nextVolume === later)
        #expect(reader.canGoForward)
        reader.closeBook()
    }

    @Test("next page before the last page stays in the same volume")
    func earlierPageStays() async throws {
        let reader = makeIsolatedReader()
        await reader.openBook(first, modelContext: context, startPage: 0)
        #expect(reader.nextVolume === second)

        reader.nextPage()
        try await waitUntil { reader.currentPage == 2 && !reader.isLoading }

        #expect(reader.currentBook === first)
        #expect(reader.currentPage == 2)
        reader.closeBook()
    }

    @Test("closing the reader while the next volume opens drops that volume")
    func closeDuringVolumeChange() async throws {
        let reader = makeIsolatedReader()
        await reader.openBook(first, modelContext: context, startPage: 3)

        reader.nextPage()
        reader.closeBook()
        try await Task.sleep(for: .milliseconds(200))

        #expect(reader.currentBook == nil)
    }
}
