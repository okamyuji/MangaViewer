import AppKit
import Foundation
import ZIPFoundation

final class ZipExtractor: PageProvider, @unchecked Sendable {
    private let archive: Archive
    private let imageEntries: [Entry]
    private let lock = NSLock()
    let pageCount: Int

    init(url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw MangaViewerError.archiveNotFound
        }

        let archive = try Archive(url: url, accessMode: .read)
        self.archive = archive

        let allEntries = archive.compactMap { entry -> (String, Entry)? in
            guard entry.type == .file else { return nil }
            let path = entry.path
            guard ImageFileFilter.isImageFile(path) else { return nil }
            return (path, entry)
        }

        let sortedPaths = ImageFileFilter.sortedNaturally(allEntries.map(\.0))
        let entryMap = Dictionary(uniqueKeysWithValues: allEntries)
        self.imageEntries = sortedPaths.compactMap { entryMap[$0] }
        self.pageCount = imageEntries.count
    }

    func image(at index: Int) async throws -> NSImage {
        guard index >= 0 && index < imageEntries.count else {
            throw MangaViewerError.pageOutOfRange(index, imageEntries.count)
        }

        let entry = imageEntries[index]
        let imageData = try extractEntry(entry)

        guard let image = NSImage(data: imageData) else {
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
