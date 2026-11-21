import Foundation
import os.log

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "MangaViewer", category: "CoordinatedRead"
)

enum CoordinatedRead {
    /// On iPad, books picked from the Files app may live in a file provider such as iCloud Drive,
    /// and Apple ("Providing access to directories") requires reading them through
    /// NSFileCoordinator, which also downloads a file that is not on the device yet.
    /// Check existence inside `body`: before the download the file is not there.
    static func read<T>(_ url: URL, _ body: (URL) throws -> T) throws -> T {
        #if os(iOS)
            var result: Result<T, Error>?
            var coordinationError: NSError?
            NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { readable in
                result = Result { try body(readable) }
            }
            if let coordinationError {
                logger.error("Coordinated read of \(url.path) failed: \(coordinationError)")
                throw coordinationError
            }
            guard let result else { throw CocoaError(.fileReadUnknown) }
            return try result.get()
        #else
            return try body(url)
        #endif
    }
}
