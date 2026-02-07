import Darwin
import Foundation
import os.log

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "MangaViewer", category: "LibraryWatcher"
)

@Observable
@MainActor
final class LibraryWatcher {
    /// Protected by `sourcesLock` so `nonisolated deinit` can safely cancel without racing
    /// with @MainActor-isolated mutations.
    @ObservationIgnored
    private nonisolated(unsafe) var sources: [URL: (source: any DispatchSourceFileSystemObject, fd: Int32)] =
        [:]
    @ObservationIgnored
    private let sourcesLock = NSLock()
    private var watchedRoots: Set<URL> = []
    private let debounceInterval: TimeInterval = 2.0
    private var debounceWorkItem: DispatchWorkItem?
    /// Maximum number of file descriptors used for watching directories.
    /// Beyond this limit, only root directories are watched; subdirectory changes
    /// are picked up by the full rescan triggered via onFilesChanged.
    private let maxWatchedDirectories = 50

    var onFilesChanged: (() -> Void)?

    func watch(folder: URL) {
        guard !watchedRoots.contains(folder) else { return }
        watchedRoots.insert(folder)
        watchDirectoryRecursively(folder)
    }

    func unwatch(folder: URL) {
        watchedRoots.remove(folder)

        let folderPath = folder.standardizedFileURL.path
        let folderPathSlash = folderPath.hasSuffix("/") ? folderPath : folderPath + "/"
        sourcesLock.lock()
        let keysToRemove = sources.keys.filter {
            let keyPath = $0.standardizedFileURL.path
            return keyPath == folderPath || keyPath.hasPrefix(folderPathSlash)
        }
        var removed: [any DispatchSourceFileSystemObject] = []
        for url in keysToRemove {
            if let entry = sources.removeValue(forKey: url) {
                removed.append(entry.source)
            }
        }
        sourcesLock.unlock()
        for source in removed {
            source.cancel()
        }
    }

    func unwatchAll() {
        sourcesLock.lock()
        let snapshot = sources.values.map(\.source)
        sources.removeAll()
        sourcesLock.unlock()
        for source in snapshot {
            source.cancel()
        }
        watchedRoots.removeAll()
    }

    private func watchDirectoryRecursively(_ url: URL) {
        watchDirectory(url)

        let maxDirs = maxWatchedDirectories
        sourcesLock.lock()
        let currentCount = sources.count
        sourcesLock.unlock()
        guard currentCount < maxDirs else {
            logger.info("FD limit reached (\(maxDirs)); skipping subdirectory watchers for \(url.path)")
            return
        }

        let fileManager = FileManager.default
        guard
            let enumerator = fileManager.enumerator(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        else { return }

        for case let subURL as URL in enumerator {
            sourcesLock.lock()
            let count = sources.count
            sourcesLock.unlock()
            if count >= maxDirs {
                logger.info("FD limit reached (\(maxDirs)); remaining subdirectories watched via rescan")
                break
            }
            guard
                let values = try? subURL.resourceValues(forKeys: [.isDirectoryKey]),
                values.isDirectory == true
            else { continue }
            watchDirectory(subURL)
        }
    }

    private func watchDirectory(_ url: URL) {
        sourcesLock.lock()
        let alreadyWatching = sources[url] != nil
        sourcesLock.unlock()
        guard !alreadyWatching else { return }

        let accessing = url.startAccessingSecurityScopedResource()

        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
            logger.warning("Failed to open directory for watching: \(url.path)")
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete, .extend],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            self?.handleChange()
        }

        source.setCancelHandler {
            close(fd)
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        source.resume()
        sourcesLock.lock()
        sources[url] = (source, fd)
        sourcesLock.unlock()
    }

    private func handleChange() {
        debounceWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.onFilesChanged?()
        }

        debounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
    }

    nonisolated deinit {
        sourcesLock.lock()
        let snapshot = sources.values.map(\.source)
        sources.removeAll()
        sourcesLock.unlock()
        for source in snapshot {
            source.cancel()
        }
    }
}
