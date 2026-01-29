import Combine
import Foundation

@Observable
final class LibraryWatcher {
    private var streams: [URL: FSEventStreamRef] = [:]
    private var watchedFolders: Set<URL> = []
    private let debounceInterval: TimeInterval = 1.0
    private var debounceWorkItem: DispatchWorkItem?

    var onFilesChanged: (() -> Void)?

    func watch(folder: URL) {
        guard !watchedFolders.contains(folder) else { return }
        watchedFolders.insert(folder)

        let path = folder.path as CFString
        let pathsToWatch = [path] as CFArray

        var context = FSEventStreamContext()
        context.info = Unmanaged.passUnretained(self).toOpaque()

        guard
            let stream = FSEventStreamCreate(
                nil,
                { _, contextInfo, _, _, _, _ in
                    guard let contextInfo else { return }
                    let watcher = Unmanaged<LibraryWatcher>.fromOpaque(contextInfo).takeUnretainedValue()
                    watcher.handleEvents()
                },
                &context,
                pathsToWatch,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                debounceInterval,
                FSEventStreamCreateFlags(
                    kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents
                )
            )
        else {
            return
        }

        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        FSEventStreamStart(stream)
        streams[folder] = stream
    }

    func unwatch(folder: URL) {
        guard let stream = streams[folder] else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        streams.removeValue(forKey: folder)
        watchedFolders.remove(folder)
    }

    func unwatchAll() {
        for folder in watchedFolders {
            unwatch(folder: folder)
        }
    }

    private func handleEvents() {
        debounceWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.onFilesChanged?()
        }

        debounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
    }

    deinit {
        unwatchAll()
    }
}
