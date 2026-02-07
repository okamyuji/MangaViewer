import Foundation
import os.log

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "MangaViewer", category: "BookmarkManager"
)

actor SecurityScopedBookmarkManager {
    static let shared = SecurityScopedBookmarkManager()

    private let bookmarkKey = "securityScopedBookmarks"
    private var activeURLs: Set<URL> = []

    private init() {}

    func saveBookmark(for url: URL) {
        do {
            let bookmarkData = try url.bookmarkData(
                options: .withSecurityScope,
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
                options: .withSecurityScope,
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
                    options: .withSecurityScope,
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
        guard let data = bookmarks[path] else { return nil }

        guard let resolved = resolveAndAccess(bookmarkData: data) else {
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
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else {
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
            UserDefaults.standard.set(data, forKey: bookmarkKey)
        } catch {
            logger.error("Failed to save bookmarks: \(error)")
        }
    }
}
