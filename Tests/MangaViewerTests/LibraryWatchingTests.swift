import Foundation
import SwiftData
import Testing
@testable import MangaViewer

@MainActor
private func makeContext() throws -> ModelContext {
    let schema = Schema([Book.self, ReadingProgress.self, Bookmark.self, Tag.self])
    let container = try ModelContainer(
        for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
    )
    return ModelContext(container)
}

private func makeIsolatedSettingsStore() -> UserDefaults {
    UserDefaults(suiteName: "MangaViewerTests.\(UUID().uuidString)")!
}

private func makeFolderWithSampleBook(pages: Int) throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try SampleBook.writeCBZ(to: folder.appendingPathComponent("sample.cbz"), pageCount: pages)
    return folder
}

@Suite("Library watching Tests", .serialized)
@MainActor
struct LibraryWatchingTests {
    @Test("rescanning watched folders imports each archive once")
    func rescanImportsOnce() async throws {
        let context = try makeContext()
        let settings = SettingsViewModel(store: makeIsolatedSettingsStore())
        try await settings.addWatchedFolder(makeFolderWithSampleBook(pages: 3))
        let library = LibraryViewModel(modelContext: context, startWatching: false, settings: settings)

        await library.rescanWatchedFolders()
        await library.rescanWatchedFolders()

        let books = try context.fetch(FetchDescriptor<Book>())
        #expect(books.count == 1)
        #expect(books.first?.title == "sample")
        #expect(books.first?.totalPages == 3)
        #expect(books.first?.thumbnailData != nil)
    }

    @Test("overlapping rescans (launch scan plus pull-to-refresh) import each archive once")
    func overlappingRescansImportOnce() async throws {
        let context = try makeContext()
        let settings = SettingsViewModel(store: makeIsolatedSettingsStore())
        let folder = try makeFolderWithSampleBook(pages: 2)
        for index in 1 ... 5 {
            try SampleBook.writeCBZ(to: folder.appendingPathComponent("extra\(index).cbz"), pageCount: 2)
        }
        await settings.addWatchedFolder(folder)
        let library = LibraryViewModel(modelContext: context, startWatching: false, settings: settings)

        async let first: Void = library.rescanWatchedFolders()
        async let second: Void = library.rescanWatchedFolders()
        _ = await (first, second)

        #expect(try context.fetchCount(FetchDescriptor<Book>()) == 6)
    }

    @Test("a folder added in Settings is imported without restarting the app")
    func addedFolderIsImported() async throws {
        let context = try makeContext()
        let settings = SettingsViewModel(store: makeIsolatedSettingsStore())
        let library = LibraryViewModel(modelContext: context, startWatching: true, settings: settings)

        try await settings.addWatchedFolder(makeFolderWithSampleBook(pages: 2))

        var count = 0
        for _ in 0 ..< 50 where count == 0 {
            try await Task.sleep(for: .milliseconds(100))
            count = try context.fetchCount(FetchDescriptor<Book>())
        }
        #expect(count == 1)
        _ = library
    }

    @Test("a watched folder without archives imports nothing")
    func emptyFolderImportsNothing() async throws {
        let context = try makeContext()
        let settings = SettingsViewModel(store: makeIsolatedSettingsStore())
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("text".utf8).write(to: folder.appendingPathComponent("readme.txt"))
        await settings.addWatchedFolder(folder)
        let library = LibraryViewModel(modelContext: context, startWatching: false, settings: settings)

        await library.rescanWatchedFolders()

        #expect(try context.fetchCount(FetchDescriptor<Book>()) == 0)
    }
}

@Suite("Reader defaults Tests")
@MainActor
struct ReaderDefaultsTests {
    @Test("a new reader starts with the reading direction and zoom chosen in Settings")
    func readerUsesSettingsDefaults() {
        let settings = SettingsViewModel(store: makeIsolatedSettingsStore())
        settings.readingDirection = .leftToRight
        settings.zoomMode = .fitWidth

        let reader = ReaderViewModel(settings: settings)

        #expect(reader.readingDirection == .leftToRight)
        #expect(reader.zoomMode == .fitWidth)
    }

    @Test("without saved settings the reader starts right-to-left and fit-page")
    func readerFallsBackToBuiltInDefaults() {
        let reader = ReaderViewModel(settings: SettingsViewModel(store: makeIsolatedSettingsStore()))

        #expect(reader.readingDirection == .rightToLeft)
        #expect(reader.zoomMode == .fitPage)
    }
}

/// A reader whose defaults come from an empty, per-test settings store.
@MainActor
func makeIsolatedReader() -> ReaderViewModel {
    ReaderViewModel(settings: SettingsViewModel(store: makeIsolatedSettingsStore()))
}
