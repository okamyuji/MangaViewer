import Foundation
import SwiftData

@Observable
@MainActor
final class LibraryViewModel {
    private let modelContext: ModelContext
    private let libraryWatcher = LibraryWatcher()

    private let settingsViewModel: SettingsViewModel
    private var isRefreshing = false

    @ObservationIgnored
    private nonisolated(unsafe) var folderObservers: [any NSObjectProtocol] = []

    init(modelContext: ModelContext, startWatching: Bool = true, settings: SettingsViewModel = SettingsViewModel()) {
        self.modelContext = modelContext
        settingsViewModel = settings
        if startWatching {
            setupWatcher()
            Task {
                await rescanWatchedFolders()
            }
        }
    }

    nonisolated deinit {
        for observer in folderObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func setupWatcher() {
        libraryWatcher.onFilesChanged = { [weak self] in
            Task { @MainActor in
                self?.refreshLibrary()
            }
        }
        let center = NotificationCenter.default
        folderObservers.append(center.addObserver(
            forName: .watchedFolderRemoved,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let url = notification.object as? URL else { return }
            Task { @MainActor in
                self?.libraryWatcher.unwatch(folder: url)
            }
        })
        folderObservers.append(center.addObserver(
            forName: .watchedFolderAdded,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let url = notification.object as? URL else { return }
            Task { @MainActor in
                await self?.scanWatchedFolder(path: url.path)
            }
        })
    }

    func addFolder(_ url: URL) async {
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
            // A picked folder joins the watched folders, so books added to it later are imported too
            _ = await settingsViewModel.registerWatchedFolder(url)
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

        #if os(macOS)
            libraryWatcher.watch(folder: folderURL)
        #endif
    }

    /// Scans a folder for supported book files, filtering out already-known paths.
    /// Runs off-MainActor to avoid blocking the UI with file-system IO.
    private nonisolated static func findNewBookFiles(
        in folderURL: URL, excluding existingPaths: Set<String>
    ) -> [URL] {
        (try? CoordinatedRead.read(folderURL) { enumerateBookFiles(in: $0, excluding: existingPaths) }) ?? []
    }

    private nonisolated static func enumerateBookFiles(
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

        // Another scan of the same folder may have inserted this file while we were awaiting.
        // The check and the insert below run on MainActor without a suspension point between them.
        let filePath = info.filePath
        let duplicates = FetchDescriptor<Book>(predicate: #Predicate { $0.filePath == filePath })
        guard (try? modelContext.fetchCount(duplicates)) == 0 else { return }

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
                options: BookmarkOptions.creation,
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

    /// Re-reads every watched folder. On macOS the folders are also (re)watched for changes;
    /// iPadOS relies on this rescan at launch and on pull-to-refresh instead.
    func rescanWatchedFolders() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let urls = await settingsViewModel.restoreWatchedFolderAccess()
        for url in urls {
            await scanFolder(url)
            // Balance the startAccessing call; watcher manages its own access per-directory
            await SecurityScopedBookmarkManager.shared.stopAccessing(url: url)
        }
    }

    private func scanWatchedFolder(path: String) async {
        guard let access = await SecurityScopedBookmarkManager.shared.startAccessing(path: path) else { return }
        await scanFolder(access.url)
        await SecurityScopedBookmarkManager.shared.stopAccessing(url: access.url)
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
