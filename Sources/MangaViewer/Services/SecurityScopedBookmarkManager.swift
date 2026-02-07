import Foundation

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
            print("Failed to save bookmark for \(url.path): \(error)")
        }
    }

    /// Returns `(resolvedURL, oldPath)` tuple. `oldPath` is non-nil when the bookmark was stale
    /// and the resolved path differs from the requested path.
    @discardableResult
    func startAccessing(path: String) -> (url: URL, oldPath: String?)? {
        let bookmarks = loadAllBookmarkData()
        guard let data = bookmarks[path] else { return nil }

        var isStale = false
        let url: URL
        do {
            url = try URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        } catch {
            print("Failed to resolve bookmark for \(path): \(error)")
            return nil
        }

        var oldPath: String?

        if isStale {
            if let newData = try? url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ) {
                var bookmarks = loadAllBookmarkData()
                if url.path != path {
                    bookmarks.removeValue(forKey: path)
                    oldPath = path
                }
                bookmarks[url.path] = newData
                saveAllBookmarkData(bookmarks)
            }
        }

        guard url.startAccessingSecurityScopedResource() else {
            return nil
        }
        activeURLs.insert(url)

        return (url, oldPath)
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
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey),
              let bookmarks = try? JSONDecoder().decode([String: Data].self, from: data)
        else {
            return [:]
        }
        return bookmarks
    }

    private func saveAllBookmarkData(_ bookmarks: [String: Data]) {
        do {
            let data = try JSONEncoder().encode(bookmarks)
            UserDefaults.standard.set(data, forKey: bookmarkKey)
        } catch {
            print("Failed to save bookmarks: \(error)")
        }
    }
}
