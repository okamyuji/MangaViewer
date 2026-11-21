import Foundation
import Unrar

final class RarExtractor: PageProvider, @unchecked Sendable {
    private let archive: Archive
    private let url: URL
    private let imageEntries: [Entry]
    private let lock = NSLock()
    let pageCount: Int

    init(url: URL) throws {
        self.url = url
        archive = try CoordinatedRead.read(url) { readable in
            guard FileManager.default.fileExists(atPath: readable.path) else {
                throw MangaViewerError.archiveNotFound
            }
            do {
                return try Archive(fileURL: readable)
            } catch {
                throw MangaViewerError.extractionFailed(
                    "Failed to open RAR archive: \(error.localizedDescription)"
                )
            }
        }

        do {
            let allEntries = try archive.entries()
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
        lock.lock()
        defer { lock.unlock() }

        do {
            // Unrar reopens the file for every extraction, so each one is a coordinated read
            return try CoordinatedRead.read(url) { _ in try archive.extract(entry) }
        } catch {
            throw MangaViewerError.extractionFailed("Failed to extract: \(error.localizedDescription)")
        }
    }

    func close() {
        // Archive is automatically closed when deallocated
    }
}
