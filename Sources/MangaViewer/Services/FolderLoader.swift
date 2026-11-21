import Foundation

final class FolderLoader: PageProvider, Sendable {
    private let imageFiles: [URL]

    var pageCount: Int {
        imageFiles.count
    }

    init(url: URL) throws {
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
        CoordinatedRead.read(directory) { enumerateImageFiles(in: $0) } ?? []
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

        for case let fileURL as URL in enumerator where ImageFileFilter.isImageFile(fileURL) {
            results.append(fileURL)
        }

        return results
    }

    func image(at index: Int) async throws -> PlatformImage {
        guard index >= 0 && index < imageFiles.count else {
            throw MangaViewerError.pageOutOfRange(index, imageFiles.count)
        }

        let fileURL = imageFiles[index]

        guard let data = CoordinatedRead.read(fileURL, { try? Data(contentsOf: $0) }) ?? nil, let image = PlatformImage(imageData: data) else {
            throw MangaViewerError.invalidImageData
        }

        return image
    }

    func close() {
        // Nothing to clean up for folder loader
    }
}
