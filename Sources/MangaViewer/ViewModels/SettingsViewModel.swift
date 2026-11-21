import Foundation
import SwiftUI

extension Notification.Name {
    static let watchedFolderRemoved = Notification.Name("MangaViewerWatchedFolderRemoved")
    static let watchedFolderAdded = Notification.Name("MangaViewerWatchedFolderAdded")
}

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

    init(store: UserDefaults = .standard) {
        _storedReadingDirection = AppStorage(
            wrappedValue: ReadingDirection.rightToLeft.rawValue, "defaultReadingDirection", store: store
        )
        _storedZoomMode = AppStorage(wrappedValue: ZoomMode.fitPage.rawValue, "defaultZoomMode", store: store)
        _storedWatchedFolders = AppStorage(wrappedValue: Data(), "watchedFolders", store: store)
    }

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

    /// Returns false without adding the folder when no bookmark can be saved for it: without one
    /// the folder could never be read again after the picker's access ends.
    @discardableResult
    func addWatchedFolder(_ url: URL) async -> Bool {
        let accessing = url.startAccessingSecurityScopedResource()
        let saved = await SecurityScopedBookmarkManager.shared.saveBookmark(for: url)
        if accessing {
            url.stopAccessingSecurityScopedResource()
        }
        guard saved else { return false }
        var folders = watchedFolders
        if !folders.contains(url) {
            folders.append(url)
            watchedFolders = folders
        }
        NotificationCenter.default.post(name: .watchedFolderAdded, object: url)
        return true
    }

    func removeWatchedFolder(_ url: URL) async {
        await SecurityScopedBookmarkManager.shared.removeBookmark(for: url.path)
        await SecurityScopedBookmarkManager.shared.stopAccessing(url: url)
        var folders = watchedFolders
        folders.removeAll { $0 == url }
        watchedFolders = folders
        NotificationCenter.default.post(name: .watchedFolderRemoved, object: url)
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
                if result.oldPath != nil {
                    folders[index] = result.url
                    updated = true
                }
            }
        }
        if updated {
            watchedFolders = folders
        }
        return urls
    }
}
