import Foundation
import Unrar

final class RarExtractor: PageProvider, @unchecked Sendable {
    private let url: URL
    private let imageEntries: [Entry]
    private let lock = NSLock()
    private let maxEntryBytes: Int64
    let pageCount: Int

    init(url: URL, maxEntryBytes: Int64 = Constants.Limits.maxPageBytes) throws {
        self.url = url
        self.maxEntryBytes = maxEntryBytes
        // Unrar reopens the file by URL for every call, so the listing happens inside the read
        let allEntries = try CoordinatedRead.read(url) { readable in
            guard FileManager.default.fileExists(atPath: readable.path) else {
                throw MangaViewerError.archiveNotFound
            }
            do {
                return try Archive(fileURL: readable).entries()
            } catch {
                throw MangaViewerError.extractionFailed(
                    "Failed to open RAR archive: \(error.localizedDescription)"
                )
            }
        }

        do {
            let imageOnlyEntries = allEntries.filter { entry in
                !entry.directory && ImageFileFilter.isImageFile(entry.fileName)
            }

            // A malformed archive can store one name twice; keep the first instead of trapping
            let entryMap = Dictionary(
                imageOnlyEntries.map { ($0.fileName, $0) }, uniquingKeysWith: { first, _ in first }
            )
            let sortedNames = ImageFileFilter.sortedNaturally(Array(entryMap.keys))
            imageEntries = sortedNames.compactMap { entryMap[$0] }
            pageCount = imageEntries.count

            if imageEntries.isEmpty {
                throw MangaViewerError.extractionFailed("No image files found in archive")
            }
        } catch let error as MangaViewerError {
            throw error
        } catch {
            throw MangaViewerError.extractionFailed(
                "Failed to read RAR archive: \(error.localizedDescription)"
            )
        }
    }

    func image(at index: Int) async throws -> PlatformImage {
        guard index >= 0 && index < imageEntries.count else {
            throw MangaViewerError.pageOutOfRange(index, imageEntries.count)
        }

        let entry = imageEntries[index]
        let imageData = try extractEntry(entry)

        guard let image = PlatformImage(imageData: imageData) else {
            throw MangaViewerError.invalidImageData
        }

        return image
    }

    private func extractEntry(_ entry: Entry) throws -> Data {
        // unrar inflates an entry only up to the unpacked size in its header
        guard entry.uncompressedSize <= UInt64(maxEntryBytes) else {
            throw MangaViewerError.pageTooLarge
        }
        lock.lock()
        defer { lock.unlock() }

        do {
            // Unrar finds the entry by name, so an archive opened at the coordinated URL works
            return try CoordinatedRead.read(url) { readable in try Archive(fileURL: readable).extract(entry) }
        } catch {
            throw MangaViewerError.extractionFailed("Failed to extract: \(error.localizedDescription)")
        }
    }

    func close() {
        // Archive is automatically closed when deallocated
    }
}
