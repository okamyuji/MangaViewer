import Darwin
import Foundation

@Observable
@MainActor
final class LibraryWatcher {
    private var sources: [URL: (source: any DispatchSourceFileSystemObject, fd: Int32)] = [:]
    private var watchedFolders: Set<URL> = []
    private let debounceInterval: TimeInterval = 2.0
    private var debounceWorkItem: DispatchWorkItem?

    var onFilesChanged: (() -> Void)?

    func watch(folder: URL) {
        guard !watchedFolders.contains(folder) else { return }

        let accessing = folder.startAccessingSecurityScopedResource()

        let fd = open(folder.path, O_EVTONLY)
        guard fd >= 0 else {
            if accessing {
                folder.stopAccessingSecurityScopedResource()
            }
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
                folder.stopAccessingSecurityScopedResource()
            }
        }

        source.resume()

        sources[folder] = (source, fd)
        watchedFolders.insert(folder)
    }

    func unwatch(folder: URL) {
        guard let entry = sources[folder] else { return }
        entry.source.cancel()
        sources.removeValue(forKey: folder)
        watchedFolders.remove(folder)
    }

    func unwatchAll() {
        for folder in Array(watchedFolders) {
            unwatch(folder: folder)
        }
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
        // DispatchSource cancel handlers will close file descriptors
        // and stop security-scoped resource access
        MainActor.assumeIsolated {
            for entry in sources.values {
                entry.source.cancel()
            }
        }
    }
}
