import Foundation
import os.log

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "MangaViewer", category: "BookmarkManager"
)

/// iOS has no `.withSecurityScope`; a plain bookmark of a document-picker URL resolves to a
/// security-scoped URL there (Apple: "Providing access to directories").
enum BookmarkOptions {
    #if os(macOS)
        static let creation: URL.BookmarkCreationOptions = .withSecurityScope
        static let resolution: URL.BookmarkResolutionOptions = .withSecurityScope
    #else
        static let creation: URL.BookmarkCreationOptions = .minimalBookmark
        static let resolution: URL.BookmarkResolutionOptions = []
    #endif
}

actor SecurityScopedBookmarkManager {
    static let shared = SecurityScopedBookmarkManager(store: makeStore())

    private let bookmarkKey = "securityScopedBookmarks"
    private let store: UserDefaults
    private var activeURLs: Set<URL> = []

    private init(store: UserDefaults) {
        self.store = store
    }

    /// Unit tests run inside the app, so they get an emptied store of their own instead of
    /// adding temporary folders to the bookmarks the real app uses.
    private static func makeStore() -> UserDefaults {
        guard AppEnvironment.isRunningUnitTests else { return .standard }
        let suiteName = "MangaViewer.UnitTests"
        UserDefaults().removePersistentDomain(forName: suiteName)
        return UserDefaults(suiteName: suiteName) ?? .standard
    }

    func saveBookmark(for url: URL) {
        do {
            let bookmarkData = try url.bookmarkData(
                options: BookmarkOptions.creation,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            var bookmarks = loadAllBookmarkData()
            bookmarks[url.path] = bookmarkData
            saveAllBookmarkData(bookmarks)
        } catch {
            logger.error("Failed to save bookmark for \(url.path): \(error)")
        }
    }

    struct ResolvedBookmark {
        let url: URL
        let bookmarkData: Data
        let isStale: Bool
    }

    /// Resolves bookmark data to a security-scoped URL.
    /// Returns the resolved URL, updated bookmark data (if stale), and starts accessing.
    func resolveAndAccess(bookmarkData: Data) -> ResolvedBookmark? {
        var isStale = false
        let url: URL
        do {
            url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: BookmarkOptions.resolution,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        } catch {
            logger.error("Failed to resolve bookmark: \(error)")
            return nil
        }

        guard url.startAccessingSecurityScopedResource() else {
            logger.warning("Failed to start accessing security-scoped resource: \(url.path)")
            return nil
        }
        activeURLs.insert(url)

        var updatedData = bookmarkData
        if isStale {
            do {
                updatedData = try url.bookmarkData(
                    options: BookmarkOptions.creation,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
            } catch {
                logger.warning("Failed to refresh stale bookmark: \(error)")
            }
        }

        return ResolvedBookmark(url: url, bookmarkData: updatedData, isStale: isStale)
    }

    /// Returns `(resolvedURL, oldPath)` tuple. `oldPath` is non-nil when the bookmark was stale
    /// and the resolved path differs from the requested path.
    @discardableResult
    func startAccessing(path: String) -> (url: URL, oldPath: String?)? {
        let bookmarks = loadAllBookmarkData()
        guard let data = bookmarks[path], let resolved = resolveAndAccess(bookmarkData: data) else {
            return nil
        }

        var oldPath: String?
        if resolved.isStale {
            var bookmarks = loadAllBookmarkData()
            if resolved.url.path != path {
                bookmarks.removeValue(forKey: path)
                oldPath = path
            }
            bookmarks[resolved.url.path] = resolved.bookmarkData
            saveAllBookmarkData(bookmarks)
        }

        return (resolved.url, oldPath)
    }

    func stopAccessing(url: URL) {
        if activeURLs.contains(url) {
            url.stopAccessingSecurityScopedResource()
            activeURLs.remove(url)
        }
    }

    func removeBookmark(for path: String) {
        var bookmarks = loadAllBookmarkData()
        bookmarks.removeValue(forKey: path)
        saveAllBookmarkData(bookmarks)
    }

    func stopAll() {
        for url in activeURLs {
            url.stopAccessingSecurityScopedResource()
        }
        activeURLs.removeAll()
    }

    // MARK: - Private

    private func loadAllBookmarkData() -> [String: Data] {
        guard let data = store.data(forKey: bookmarkKey) else {
            return [:]
        }
        do {
            return try JSONDecoder().decode([String: Data].self, from: data)
        } catch {
            logger.error("Failed to decode bookmark data: \(error)")
            return [:]
        }
    }

    private func saveAllBookmarkData(_ bookmarks: [String: Data]) {
        do {
            let data = try JSONEncoder().encode(bookmarks)
            store.set(data, forKey: bookmarkKey)
        } catch {
            logger.error("Failed to save bookmarks: \(error)")
        }
    }
}
