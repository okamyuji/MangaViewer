import Darwin
import Foundation
import os.log

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "MangaViewer", category: "LibraryWatcher"
)

@Observable
@MainActor
final class LibraryWatcher {
    private var sources: [URL: (source: any DispatchSourceFileSystemObject, fd: Int32)] = [:]
    private var watchedRoots: Set<URL> = []
    private let debounceInterval: TimeInterval = 2.0
    private var debounceWorkItem: DispatchWorkItem?

    var onFilesChanged: (() -> Void)?

    func watch(folder: URL) {
        guard !watchedRoots.contains(folder) else { return }
        watchedRoots.insert(folder)
        watchDirectoryRecursively(folder)
    }

    func unwatch(folder: URL) {
        watchedRoots.remove(folder)

        let keysToRemove = sources.keys.filter { $0.path.hasPrefix(folder.path) }
        for url in keysToRemove {
            if let entry = sources.removeValue(forKey: url) {
                entry.source.cancel()
            }
        }
    }

    func unwatchAll() {
        for entry in sources.values {
            entry.source.cancel()
        }
        sources.removeAll()
        watchedRoots.removeAll()
    }

    private func watchDirectoryRecursively(_ url: URL) {
        watchDirectory(url)

        // Watch subdirectories recursively
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for case let subURL as URL in enumerator {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: subURL.path, isDirectory: &isDir), isDir.boolValue {
                watchDirectory(subURL)
            }
        }
    }

    private func watchDirectory(_ url: URL) {
        guard sources[url] == nil else { return }

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
        sources[url] = (source, fd)
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
        // DispatchSource cancel handlers handle fd close and resource cleanup
        // Sources are cleaned up via unwatchAll() during app lifecycle
    }
}
