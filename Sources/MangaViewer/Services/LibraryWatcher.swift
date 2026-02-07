import Darwin
import Foundation
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "MangaViewer", category: "LibraryWatcher")

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

        watchDirectory(folder)

        let fileManager = FileManager.default
        guard
            let enumerator = fileManager.enumerator(
                at: folder,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        else {
            return
        }

        for case let subURL as URL in enumerator {
            let isDir =
                (try? subURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir {
                watchDirectory(subURL)
            }
        }
    }

    func unwatch(folder: URL) {
        watchedRoots.remove(folder)

        for url in sources.keys where url.path.hasPrefix(folder.path) {
            if let entry = sources[url] {
                entry.source.cancel()
                sources.removeValue(forKey: url)
            }
        }
    }

    func unwatchAll() {
        for url in Array(sources.keys) {
            if let entry = sources[url] {
                entry.source.cancel()
            }
        }
        sources.removeAll()
        watchedRoots.removeAll()
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
        MainActor.assumeIsolated {
            for entry in sources.values {
                entry.source.cancel()
            }
        }
    }
}
