import AppKit
import Foundation
import SwiftUI

@Observable
final class SettingsViewModel {
    @ObservationIgnored
    @AppStorage("defaultReadingDirection")
    private var storedReadingDirection: String = ReadingDirection.rightToLeft.rawValue

    @ObservationIgnored
    @AppStorage("defaultDisplayMode") private var storedDisplayMode: String = DisplayMode.spread
        .rawValue

    @ObservationIgnored
    @AppStorage("defaultZoomMode") private var storedZoomMode: String = ZoomMode.fitPage.rawValue

    @ObservationIgnored
    @AppStorage("watchedFolders") private var storedWatchedFolders: Data = .init()

    var readingDirection: ReadingDirection {
        get { ReadingDirection(rawValue: storedReadingDirection) ?? .rightToLeft }
        set { storedReadingDirection = newValue.rawValue }
    }

    var displayMode: DisplayMode {
        get { DisplayMode(rawValue: storedDisplayMode) ?? .spread }
        set { storedDisplayMode = newValue.rawValue }
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

    func addWatchedFolder(_ url: URL) {
        SecurityScopedBookmarkManager.shared.saveBookmark(for: url)
        var folders = watchedFolders
        if !folders.contains(url) {
            folders.append(url)
            watchedFolders = folders
        }
    }

    func removeWatchedFolder(_ url: URL) {
        SecurityScopedBookmarkManager.shared.removeBookmark(for: url.path)
        SecurityScopedBookmarkManager.shared.stopAccessing(url: url)
        var folders = watchedFolders
        folders.removeAll { $0 == url }
        watchedFolders = folders
    }

    func restoreWatchedFolderAccess() -> [URL] {
        watchedFolders.compactMap { folder in
            SecurityScopedBookmarkManager.shared.startAccessing(path: folder.path)
        }
    }
}
