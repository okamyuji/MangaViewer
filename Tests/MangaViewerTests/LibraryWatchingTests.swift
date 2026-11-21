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

    @Test("a launch rescan overlapping a manual import of the same folder imports each archive once")
    func rescanAndManualImportImportOnce() async throws {
        let context = try makeContext()
        let settings = SettingsViewModel(store: makeIsolatedSettingsStore())
        let folder = try makeFolderWithSampleBook(pages: 2)
        for index in 1 ... 5 {
            try SampleBook.writeCBZ(to: folder.appendingPathComponent("extra\(index).cbz"), pageCount: 2)
        }
        await settings.addWatchedFolder(folder)
        let library = LibraryViewModel(modelContext: context, startWatching: false, settings: settings)

        async let rescan: Void = library.rescanWatchedFolders()
        async let manual: Void = library.addFolder(folder)
        _ = await (rescan, manual)

        #expect(try context.fetchCount(FetchDescriptor<Book>()) == 6)
    }

    @Test("a folder picked with Add Books is watched, so books added to it later are imported on rescan")
    func addedBooksFolderIsRescanned() async throws {
        let context = try makeContext()
        let settings = SettingsViewModel(store: makeIsolatedSettingsStore())
        let folder = try makeFolderWithSampleBook(pages: 2)
        let library = LibraryViewModel(modelContext: context, startWatching: false, settings: settings)

        await library.addFolder(folder)
        try SampleBook.writeCBZ(to: folder.appendingPathComponent("later.cbz"), pageCount: 2)
        await library.rescanWatchedFolders()

        #expect(settings.watchedFolders == [folder])
        #expect(try context.fetchCount(FetchDescriptor<Book>()) == 2)
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

    @Test("a folder whose bookmark cannot be created is not added to the watched folders")
    func unbookmarkableFolderIsRejected() async {
        let settings = SettingsViewModel(store: makeIsolatedSettingsStore())
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

        let added = await settings.addWatchedFolder(missing)

        #expect(added == false)
        #expect(settings.watchedFolders.isEmpty)
    }

    @Test("a watched folder the app can no longer access is reported instead of skipped silently")
    func inaccessibleWatchedFolderIsReported() async throws {
        let context = try makeContext()
        let settings = SettingsViewModel(store: makeIsolatedSettingsStore())
        let name = "Gone-\(UUID().uuidString)"
        settings.watchedFolders = [FileManager.default.temporaryDirectory.appendingPathComponent(name)]
        let library = LibraryViewModel(modelContext: context, startWatching: false, settings: settings)
        AppState.shared.openError = nil
        AppState.shared.showError = false
        defer {
            AppState.shared.openError = nil
            AppState.shared.showError = false
        }

        await library.rescanWatchedFolders()

        #expect(AppState.shared.showError)
        #expect(AppState.shared.openError?.contains(name) == true)

        // macOS rescans on every file change; the same folder is reported only once
        AppState.shared.showError = false
        await library.rescanWatchedFolders()
        #expect(AppState.shared.showError == false)
    }

    @Test("a reader whose open was cancelled does not keep the book it finished opening")
    func cancelledOpenIsDropped() async throws {
        let context = try makeContext()
        let folder = try makeFolderWithSampleBook(pages: 3)
        let book = Book(
            title: "sample", filePath: folder.appendingPathComponent("sample.cbz").path, type: .cbz, totalPages: 3
        )
        context.insert(book)
        let reader = makeIsolatedReader()

        let open = Task { await reader.openBook(book, modelContext: context) }
        open.cancel()
        await open.value

        #expect(reader.totalPages == 0)
    }

    @Test("a reader reopened before its previous open finished keeps only the latest book")
    func staleOpenDoesNotOverwriteNewerOpen() async throws {
        let context = try makeContext()
        // Listing thousands of files makes the first open finish after the second one
        let slowFolder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: slowFolder, withIntermediateDirectories: true)
        for index in 0 ..< 3000 {
            FileManager.default.createFile(
                atPath: slowFolder.appendingPathComponent(String(format: "p%04d.png", index)).path, contents: nil
            )
        }
        let slowBook = Book(title: "slow", filePath: slowFolder.path, type: .folder, totalPages: 3000)
        let fastFolder = try makeFolderWithSampleBook(pages: 3)
        let fastBook = Book(
            title: "sample", filePath: fastFolder.appendingPathComponent("sample.cbz").path, type: .cbz, totalPages: 3
        )
        context.insert(slowBook)
        context.insert(fastBook)
        let reader = makeIsolatedReader()

        let stale = Task { await reader.openBook(slowBook, modelContext: context) }
        await Task.yield()
        reader.closeBook()
        let latest = Task { await reader.openBook(fastBook, modelContext: context) }
        await stale.value
        await latest.value

        #expect(reader.totalPages == 3)
        #expect(reader.currentBook === fastBook)
        #expect(reader.errorMessage == nil)
        #expect(reader.isLoading == false)
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
