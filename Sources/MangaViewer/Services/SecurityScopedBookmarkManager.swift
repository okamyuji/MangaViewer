import Foundation

final class SecurityScopedBookmarkManager: @unchecked Sendable {
    static let shared = SecurityScopedBookmarkManager()

    private let queue = DispatchQueue(label: "work.okamyuji.mangaviewer.bookmark-manager")
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
            queue.sync {
                var bookmarks = loadAllBookmarkData()
                bookmarks[url.path] = bookmarkData
                saveAllBookmarkData(bookmarks)
            }
        } catch {
            print("Failed to save bookmark for \(url.path): \(error)")
        }
    }

    @discardableResult
    func startAccessing(path: String) -> URL? {
        queue.sync {
            let bookmarks = loadAllBookmarkData()
            guard let data = bookmarks[path] else { return nil }

            var isStale = false
            guard let url = try? URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else { return nil }

            if isStale {
                if let newData = try? url.bookmarkData(
                    options: .withSecurityScope,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                ) {
                    var bookmarks = loadAllBookmarkData()
                    if url.path != path {
                        bookmarks.removeValue(forKey: path)
                    }
                    bookmarks[url.path] = newData
                    saveAllBookmarkData(bookmarks)
                }
            }

            guard url.startAccessingSecurityScopedResource() else {
                return nil
            }
            activeURLs.insert(url)

            return url
        }
    }

    func stopAccessing(url: URL) {
        queue.sync {
            if activeURLs.contains(url) {
                url.stopAccessingSecurityScopedResource()
                activeURLs.remove(url)
            }
        }
    }

    func removeBookmark(for path: String) {
        queue.sync {
            var bookmarks = loadAllBookmarkData()
            bookmarks.removeValue(forKey: path)
            saveAllBookmarkData(bookmarks)
        }
    }

    func stopAll() {
        queue.sync {
            for url in activeURLs {
                url.stopAccessingSecurityScopedResource()
            }
            activeURLs.removeAll()
        }
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
