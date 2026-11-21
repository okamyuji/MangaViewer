import Foundation
import os.log

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "MangaViewer", category: "CoordinatedRead"
)

enum CoordinatedRead {
    /// On iPad, files and folders picked from the Files app may live in a file provider, and Apple
    /// ("Providing access to directories") requires reading them through NSFileCoordinator.
    /// Returns nil when coordination fails.
    static func read<T>(_ url: URL, _ body: (URL) -> T) -> T? {
        #if os(iOS)
            var result: T?
            var coordinationError: NSError?
            NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinated in
                result = body(coordinated)
            }
            if let coordinationError {
                logger.error("Coordinated read of \(url.path) failed: \(coordinationError)")
            }
            return result
        #else
            return body(url)
        #endif
    }
}
