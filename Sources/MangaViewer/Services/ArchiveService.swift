import Foundation

enum ArchiveService {
    static func provider(for url: URL) throws -> PageProvider {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
           isDirectory.boolValue {
            return try FolderLoader(url: url)
        }

        switch url.pathExtension.lowercased() {
        case "cbz", "zip":
            return try ZipExtractor(url: url)
        case "cbr", "rar":
            return try RarExtractor(url: url)
        default:
            throw MangaViewerError.unsupportedFormat
        }
    }

    static func bookType(for url: URL) -> BookType? {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
           isDirectory.boolValue {
            return .folder
        }

        switch url.pathExtension.lowercased() {
        case "cbz", "zip":
            return .cbz
        case "cbr", "rar":
            return .cbr
        default:
            return nil
        }
    }
}
