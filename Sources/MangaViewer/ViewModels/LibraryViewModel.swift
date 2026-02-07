import AppKit
import Foundation
import os.log
import SwiftData

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "MangaViewer", category: "LibraryViewModel"
)

@Observable
@MainActor
final class LibraryViewModel {
    var searchText: String = ""
    var selectedTag: Tag?
    var sortOrder: SortOrder = .title
    var isImporting: Bool = false

    private let modelContext: ModelContext
    private let libraryWatcher = LibraryWatcher()

    private let settingsViewModel = SettingsViewModel()
    private var isRefreshing = false

    @ObservationIgnored
    private nonisolated(unsafe) var folderRemovedObserver: (any NSObjectProtocol)?

    init(modelContext: ModelContext, startWatching: Bool = true) {
        self.modelContext = modelContext
        if startWatching {
            setupWatcher()
            Task {
                await restoreWatchedFolders()
            }
        }
    }

    nonisolated deinit {
        if let observer = folderRemovedObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func setupWatcher() {
        libraryWatcher.onFilesChanged = { [weak self] in
            Task { @MainActor in
                self?.refreshLibrary()
            }
        }
        folderRemovedObserver = NotificationCenter.default.addObserver(
            forName: .watchedFolderRemoved,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let url = notification.object as? URL else { return }
            Task { @MainActor in
                self?.libraryWatcher.unwatch(folder: url)
            }
        }
    }

    func addFolder(_ url: URL) async {
        isImporting = true
        defer { isImporting = false }

        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false

        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return
        }

        if isDirectory.boolValue {
            await SecurityScopedBookmarkManager.shared.saveBookmark(for: url)
            await scanFolder(url)
        } else {
            await addBook(at: url)
        }
    }

    private func scanFolder(_ folderURL: URL) async {
        // Pre-fetch all existing file paths to avoid O(N^2) per-file queries
        let existingPaths: Set<String>
        do {
            let descriptor = FetchDescriptor<Book>()
            let allBooks = try modelContext.fetch(descriptor)
            existingPaths = Set(allBooks.map(\.filePath))
        } catch {
            existingPaths = []
        }

        // Move heavy file-system enumeration off the MainActor
        let newURLs = await Task.detached {
            Self.findNewBookFiles(in: folderURL, excluding: existingPaths)
        }.value

        for fileURL in newURLs {
            await addBook(at: fileURL)
        }

        libraryWatcher.watch(folder: folderURL)
    }

    /// Scans a folder for supported book files, filtering out already-known paths.
    /// Runs off-MainActor to avoid blocking the UI with file-system IO.
    private nonisolated static func findNewBookFiles(
        in folderURL: URL, excluding existingPaths: Set<String>
    ) -> [URL] {
        let fileManager = FileManager.default
        guard
            let enumerator = fileManager.enumerator(
                at: folderURL,
                includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        else {
            return []
        }
        return enumerator.compactMap { $0 as? URL }
            .filter { ArchiveService.bookType(for: $0) != nil && !existingPaths.contains($0.path) }
    }

    private func addBook(at url: URL) async {
        // Run archive parsing, bookmark creation, and thumbnail generation off-MainActor
        let info: BookInfo? = await Task.detached {
            await Self.extractBookInfo(from: url)
        }.value

        guard let info else { return }

        // SwiftData insertion must happen on MainActor
        let book = Book(
            title: info.title,
            filePath: info.filePath,
            type: info.bookType,
            totalPages: info.totalPages
        )
        book.bookmarkData = info.bookmarkData
        book.thumbnailData = info.thumbnailData
        book.progress = ReadingProgress()

        modelContext.insert(book)
        try? modelContext.save()
    }

    /// Extracts all book metadata off-MainActor: opens archive, generates thumbnail, creates bookmark.
    private nonisolated static func extractBookInfo(from url: URL) async -> BookInfo? {
        guard let bookType = ArchiveService.bookType(for: url) else { return nil }

        do {
            let provider = try ArchiveService.provider(for: url)
            defer { provider.close() }

            let title = url.deletingPathExtension().lastPathComponent
            let bookmarkData = try? url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )

            let thumbnailData = await ThumbnailGenerator.generate(from: provider)

            return BookInfo(
                title: title,
                filePath: url.path,
                bookType: bookType,
                totalPages: provider.pageCount,
                bookmarkData: bookmarkData,
                thumbnailData: thumbnailData
            )
        } catch {
            return nil
        }
    }

    func removeBook(_ book: Book) async {
        await SecurityScopedBookmarkManager.shared.removeBookmark(for: book.filePath)
        modelContext.delete(book)
        try? modelContext.save()
    }

    func refreshLibrary() {
        guard !isRefreshing else { return }
        isRefreshing = true
        let folders = settingsViewModel.watchedFolders
        Task {
            for folder in folders {
                await scanFolder(folder)
            }
            isRefreshing = false
        }
    }

    private func restoreWatchedFolders() async {
        let urls = await settingsViewModel.restoreWatchedFolderAccess()
        for url in urls {
            libraryWatcher.watch(folder: url)
            await scanFolder(url)
            // Balance the startAccessing call; watcher manages its own access per-directory
            await SecurityScopedBookmarkManager.shared.stopAccessing(url: url)
        }
    }

    func openBookInFinder(_ book: Book) {
        let url = URL(fileURLWithPath: book.filePath)
        NSWorkspace.shared.selectFile(
            url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path
        )
    }
}

/// Value type for passing book metadata across actor boundaries.
private struct BookInfo: Sendable {
    let title: String
    let filePath: String
    let bookType: BookType
    let totalPages: Int
    let bookmarkData: Data?
    let thumbnailData: Data?
}
