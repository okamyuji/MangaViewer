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

        let fileManager = FileManager.default
        guard
            let enumerator = fileManager.enumerator(
                at: folderURL,
                includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        else {
            return
        }

        let urls = enumerator.compactMap { $0 as? URL }
        for fileURL in urls where ArchiveService.bookType(for: fileURL) != nil {
            if existingPaths.contains(fileURL.path) {
                continue
            }
            await addBook(at: fileURL)
        }

        libraryWatcher.watch(folder: folderURL)
    }

    private func addBook(at url: URL) async {
        guard let bookType = ArchiveService.bookType(for: url) else {
            return
        }

        do {
            let provider = try ArchiveService.provider(for: url)
            defer { provider.close() }

            let title = url.deletingPathExtension().lastPathComponent
            let book = Book(
                title: title,
                filePath: url.path,
                type: bookType,
                totalPages: provider.pageCount
            )

            do {
                book.bookmarkData = try url.bookmarkData(
                    options: .withSecurityScope,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
            } catch {
                logger.error("Failed to create bookmark for \(book.title): \(error)")
            }

            if let thumbnailData = await ThumbnailGenerator.generate(from: provider) {
                book.thumbnailData = thumbnailData
            }

            let progress = ReadingProgress()
            book.progress = progress

            modelContext.insert(book)
            try modelContext.save()
        } catch {
            logger.error("Failed to add book: \(error)")
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
