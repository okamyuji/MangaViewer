import Foundation
import ZIPFoundation

final class ZipExtractor: PageProvider, @unchecked Sendable {
    private let archive: Archive
    private let imageEntries: [Entry]
    private let lock = NSLock()
    private let maxEntryBytes: Int64
    private let url: URL
    let pageCount: Int

    init(url: URL, maxEntryBytes: Int64 = Constants.Limits.maxPageBytes) throws {
        self.maxEntryBytes = maxEntryBytes
        self.url = url
        // Coordinating the open brings a file-provider placeholder onto the device; each page
        // read below is coordinated as well, so the provider cannot evict the file mid-read.
        let archive = try CoordinatedRead.read(url) { readable in
            guard FileManager.default.fileExists(atPath: readable.path) else {
                throw MangaViewerError.archiveNotFound
            }
            return try Archive(url: readable, accessMode: .read)
        }
        self.archive = archive

        let allEntries = archive.compactMap { entry -> (String, Entry)? in
            guard entry.type == .file else { return nil }
            let path = entry.path
            guard ImageFileFilter.isImageFile(path) else { return nil }
            return (path, entry)
        }

        // A malformed archive can store one path twice; keep the first instead of trapping
        let entryMap = Dictionary(allEntries, uniquingKeysWith: { first, _ in first })
        let sortedPaths = ImageFileFilter.sortedNaturally(Array(entryMap.keys))
        imageEntries = sortedPaths.compactMap { entryMap[$0] }
        pageCount = imageEntries.count
    }

    func image(at index: Int) async throws -> PlatformImage {
        guard index >= 0, index < imageEntries.count else {
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
        lock.lock()
        defer { lock.unlock() }

        // The declared size can be forged (zip64 allows up to 2^64 - 1, beyond Int64), so the
        // comparison stays in UInt64 and the inflated bytes are counted as well
        guard entry.uncompressedSize <= UInt64(maxEntryBytes) else {
            throw MangaViewerError.pageTooLarge
        }
        var imageData = Data()
        do {
            _ = try CoordinatedRead.read(url) { _ in
                try archive.extract(entry) { data in
                    imageData.append(data)
                    if Int64(imageData.count) > maxEntryBytes {
                        throw MangaViewerError.pageTooLarge
                    }
                }
            }
        } catch let error as MangaViewerError {
            throw error
        } catch {
            throw MangaViewerError.extractionFailed(error.localizedDescription)
        }
        return imageData
    }

    func close() {
        // Archive is automatically closed when deallocated
    }
}
