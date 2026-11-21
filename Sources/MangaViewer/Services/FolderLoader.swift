import Foundation

final class FolderLoader: PageProvider, Sendable {
    private let imageFiles: [URL]
    private let maxPageBytes: Int64

    var pageCount: Int {
        imageFiles.count
    }

    init(url: URL, maxPageBytes: Int64 = Constants.Limits.maxPageBytes) throws {
        self.maxPageBytes = maxPageBytes
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw MangaViewerError.archiveNotFound
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            throw MangaViewerError.unsupportedFormat
        }

        let images = Self.findImageFiles(in: url)
        imageFiles = ImageFileFilter.sortedNaturally(images)

        if imageFiles.isEmpty {
            throw MangaViewerError.extractionFailed("No image files found in folder")
        }
    }

    private static func findImageFiles(in directory: URL) -> [URL] {
        (try? CoordinatedRead.read(directory) { enumerateImageFiles(in: $0) }) ?? []
    }

    private static func enumerateImageFiles(in directory: URL) -> [URL] {
        var results: [URL] = []
        let fileManager = FileManager.default

        guard
            let enumerator = fileManager.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        else {
            return results
        }

        for case let fileURL as URL in enumerator where ImageFileFilter.isPageFile(fileURL) {
            results.append(fileURL)
        }

        return results
    }

    func image(at index: Int) async throws -> PlatformImage {
        guard index >= 0, index < imageFiles.count else {
            throw MangaViewerError.pageOutOfRange(index, imageFiles.count)
        }

        let fileURL = imageFiles[index]

        let data: Data
        do {
            data = try CoordinatedRead.read(fileURL) { readable in
                // Reading one byte past the limit also catches a file that grew after it was listed
                let handle = try FileHandle(forReadingFrom: readable)
                defer { try? handle.close() }
                let bytes = try handle.read(upToCount: Int(maxPageBytes) + 1) ?? Data()
                guard Int64(bytes.count) <= maxPageBytes else {
                    throw MangaViewerError.pageTooLarge
                }
                return bytes
            }
        } catch let error as MangaViewerError {
            throw error
        } catch {
            throw MangaViewerError.invalidImageData
        }

        guard let image = PlatformImage(imageData: data) else {
            throw MangaViewerError.invalidImageData
        }
        return image
    }

    func close() {
        // Nothing to clean up for folder loader
    }
}
