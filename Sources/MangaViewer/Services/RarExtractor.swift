import AppKit
import Foundation

final class RarExtractor: PageProvider, Sendable {
    private let tempDirectory: URL
    private let imageFiles: [URL]

    var pageCount: Int {
        imageFiles.count
    }

    init(url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw MangaViewerError.archiveNotFound
        }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MangaViewer")
            .appendingPathComponent(UUID().uuidString)

        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        self.tempDirectory = tempDir

        try Self.extractArchive(from: url, to: tempDir)

        let images = Self.findImageFiles(in: tempDir)
        self.imageFiles = ImageFileFilter.sortedNaturally(images)

        if imageFiles.isEmpty {
            throw MangaViewerError.extractionFailed("No image files found in archive")
        }
    }

    private static func extractArchive(from source: URL, to destination: URL) throws {
        // Try unar first (comes with The Unarchiver, handles both RAR4 and RAR5)
        if tryExtract(executable: "/usr/local/bin/unar", arguments: ["-o", destination.path, source.path]) {
            return
        }

        // Try unar from homebrew arm64
        if tryExtract(executable: "/opt/homebrew/bin/unar", arguments: ["-o", destination.path, source.path]) {
            return
        }

        // Try 7z
        if tryExtract(executable: "/usr/local/bin/7z", arguments: ["x", "-o\(destination.path)", source.path]) {
            return
        }

        // Try 7z from homebrew arm64
        if tryExtract(executable: "/opt/homebrew/bin/7z", arguments: ["x", "-o\(destination.path)", source.path]) {
            return
        }

        // Try unrar
        let destPath = destination.path + "/"
        if tryExtract(executable: "/usr/local/bin/unrar", arguments: ["x", "-o+", source.path, destPath]) {
            return
        }

        // Try unrar from homebrew arm64
        if tryExtract(executable: "/opt/homebrew/bin/unrar", arguments: ["x", "-o+", source.path, destPath]) {
            return
        }

        throw MangaViewerError.extractionFailed(
            "Failed to extract RAR archive. Please install one of: unar, 7z, or unrar (brew install unar)"
        )
    }

    private static func tryExtract(executable: String, arguments: [String]) -> Bool {
        guard FileManager.default.fileExists(atPath: executable) else {
            return false
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private static func findImageFiles(in directory: URL) -> [URL] {
        var results: [URL] = []
        let fileManager = FileManager.default

        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return results
        }

        for case let fileURL as URL in enumerator where ImageFileFilter.isImageFile(fileURL) {
            results.append(fileURL)
        }

        return results
    }

    func image(at index: Int) async throws -> NSImage {
        guard index >= 0 && index < imageFiles.count else {
            throw MangaViewerError.pageOutOfRange(index, imageFiles.count)
        }

        let fileURL = imageFiles[index]

        guard let image = NSImage(contentsOf: fileURL) else {
            throw MangaViewerError.invalidImageData
        }

        return image
    }

    func close() {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    deinit {
        close()
    }
}
