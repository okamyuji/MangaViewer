import Foundation
import Testing
@testable import MangaViewer

private func makeTemporaryFile(named name: String) throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent(name)
    try Data("x".utf8).write(to: url)
    return url
}

@Suite("Bookmark options Tests")
struct BookmarkOptionsTests {
    @Test("a bookmark created with the platform options resolves back to the same file")
    func roundTrip() throws {
        let url = try makeTemporaryFile(named: "book.cbz")
        let data = try url.bookmarkData(
            options: BookmarkOptions.creation, includingResourceValuesForKeys: nil, relativeTo: nil
        )
        var isStale = false
        let resolved = try URL(
            resolvingBookmarkData: data, options: BookmarkOptions.resolution,
            relativeTo: nil, bookmarkDataIsStale: &isStale
        )
        #expect(resolved.resolvingSymlinksInPath().path == url.resolvingSymlinksInPath().path)
        #expect(isStale == false)
    }

    @Test("the bookmark manager stores, resolves and forgets a folder bookmark")
    func managerRoundTrip() async throws {
        let folder = try makeTemporaryFile(named: "page.png").deletingLastPathComponent()
        let manager = SecurityScopedBookmarkManager.shared
        await manager.saveBookmark(for: folder)

        let resolved = try #require(await manager.startAccessing(path: folder.path))
        #expect(resolved.url.resolvingSymlinksInPath().path == folder.resolvingSymlinksInPath().path)
        await manager.stopAccessing(url: resolved.url)

        await manager.removeBookmark(for: folder.path)
        #expect(await manager.startAccessing(path: folder.path) == nil)
    }

    @Test("unit tests keep bookmarks out of the app's real settings")
    func bookmarksStayOutOfStandardDefaults() async throws {
        let folder = try makeTemporaryFile(named: "page.png").deletingLastPathComponent()
        let before = UserDefaults.standard.data(forKey: "securityScopedBookmarks")

        await SecurityScopedBookmarkManager.shared.saveBookmark(for: folder)
        let after = UserDefaults.standard.data(forKey: "securityScopedBookmarks")
        await SecurityScopedBookmarkManager.shared.removeBookmark(for: folder.path)

        #expect(after == before)
    }
}

@Suite("AppState.openFile Tests", .serialized)
@MainActor
struct AppStateOpenFileTests {
    private func reset() {
        AppState.shared.clearFileToOpen()
        AppState.shared.openError = nil
        AppState.shared.showError = false
    }

    @Test("an existing archive is queued for opening")
    func existingArchive() throws {
        reset()
        let url = try makeTemporaryFile(named: "book.cbz")
        AppState.shared.openFile(url)
        #expect(AppState.shared.fileToOpen == url)
        #expect(AppState.shared.showError == false)
    }

    @Test("an unsupported extension is rejected with an error")
    func unsupportedExtension() throws {
        reset()
        try AppState.shared.openFile(makeTemporaryFile(named: "notes.txt"))
        #expect(AppState.shared.fileToOpen == nil)
        #expect(AppState.shared.openError == "Unsupported file format: txt")
        #expect(AppState.shared.showError)
    }

    @Test("a missing archive is rejected with an error")
    func missingArchive() {
        reset()
        AppState.shared.openFile(URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString).cbz"))
        #expect(AppState.shared.fileToOpen == nil)
        #expect(AppState.shared.openError?.hasPrefix("File not found:") == true)
    }
}
