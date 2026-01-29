import AppKit
import Foundation
import Unrar

final class RarExtractor: PageProvider, @unchecked Sendable {
    private let archive: Archive
    private let imageEntries: [Entry]
    private let lock = NSLock()
    let pageCount: Int

    init(url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw MangaViewerError.archiveNotFound
        }

        do {
            archive = try Archive(fileURL: url)
        } catch {
            throw MangaViewerError.extractionFailed(
                "Failed to open RAR archive: \(error.localizedDescription)"
            )
        }

        do {
            let allEntries = try archive.entries()
            let imageOnlyEntries = allEntries.filter { entry in
                !entry.directory && ImageFileFilter.isImageFile(entry.fileName)
            }

            let sortedNames = ImageFileFilter.sortedNaturally(imageOnlyEntries.map(\.fileName))
            let entryMap = Dictionary(uniqueKeysWithValues: imageOnlyEntries.map { ($0.fileName, $0) })
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

        do {
            return try archive.extract(entry)
        } catch {
            throw MangaViewerError.extractionFailed("Failed to extract: \(error.localizedDescription)")
        }
    }

    func close() {
        // Archive is automatically closed when deallocated
    }
}
