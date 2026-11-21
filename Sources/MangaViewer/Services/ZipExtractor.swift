import Foundation
import ZIPFoundation

final class ZipExtractor: PageProvider, @unchecked Sendable {
    private let archive: Archive
    private let imageEntries: [Entry]
    private let lock = NSLock()
    let pageCount: Int

    init(url: URL) throws {
        // Pages are read later through this open archive, so coordinating the open is enough to
        // bring a file-provider placeholder onto the device.
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

        let sortedPaths = ImageFileFilter.sortedNaturally(allEntries.map(\.0))
        // A malformed archive can store one path twice; keep the first instead of trapping
        let entryMap = Dictionary(allEntries, uniquingKeysWith: { first, _ in first })
        imageEntries = sortedPaths.compactMap { entryMap[$0] }
        pageCount = imageEntries.count
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
        lock.lock()
        defer { lock.unlock() }

        var imageData = Data()
        do {
            _ = try archive.extract(entry) { data in
                imageData.append(data)
            }
        } catch {
            throw MangaViewerError.extractionFailed(error.localizedDescription)
        }
        return imageData
    }

    func close() {
        // Archive is automatically closed when deallocated
    }
}
