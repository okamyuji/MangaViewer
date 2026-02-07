import AppKit
import Foundation
import SwiftUI

@Observable
@MainActor
final class SettingsViewModel {
    @ObservationIgnored
    @AppStorage("defaultReadingDirection")
    private var storedReadingDirection: String = ReadingDirection.rightToLeft.rawValue

    @ObservationIgnored
    @AppStorage("defaultZoomMode") private var storedZoomMode: String = ZoomMode.fitPage.rawValue

    @ObservationIgnored
    @AppStorage("watchedFolders") private var storedWatchedFolders: Data = .init()

    var readingDirection: ReadingDirection {
        get { ReadingDirection(rawValue: storedReadingDirection) ?? .rightToLeft }
        set { storedReadingDirection = newValue.rawValue }
    }

    var zoomMode: ZoomMode {
        get { ZoomMode(rawValue: storedZoomMode) ?? .fitPage }
        set { storedZoomMode = newValue.rawValue }
    }

    var watchedFolders: [URL] {
        get {
            (try? JSONDecoder().decode([URL].self, from: storedWatchedFolders)) ?? []
        }
        set {
            storedWatchedFolders = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    func addWatchedFolder(_ url: URL) async {
        await SecurityScopedBookmarkManager.shared.saveBookmark(for: url)
        var folders = watchedFolders
        if !folders.contains(url) {
            folders.append(url)
            watchedFolders = folders
        }
    }

    func removeWatchedFolder(_ url: URL) async {
        await SecurityScopedBookmarkManager.shared.removeBookmark(for: url.path)
        await SecurityScopedBookmarkManager.shared.stopAccessing(url: url)
        var folders = watchedFolders
        folders.removeAll { $0 == url }
        watchedFolders = folders
    }

    func restoreWatchedFolderAccess() async -> [URL] {
        var urls: [URL] = []
        var folders = watchedFolders
        var updated = false
        for (index, folder) in folders.enumerated() {
            if let result = await SecurityScopedBookmarkManager.shared.startAccessing(
                path: folder.path
            ) {
                urls.append(result.url)
                if let oldPath = result.oldPath, result.url != folder {
                    folders[index] = result.url
                    updated = true
                    _ = oldPath // Consumed by bookmark manager internally
                }
            }
        }
        if updated {
            watchedFolders = folders
        }
        return urls
    }
}
