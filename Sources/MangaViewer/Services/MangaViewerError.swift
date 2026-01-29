import Foundation

enum MangaViewerError: LocalizedError {
    case archiveNotFound
    case unsupportedFormat
    case extractionFailed(String)
    case invalidImageData
    case pageOutOfRange(Int, Int)

    var errorDescription: String? {
        switch self {
        case .archiveNotFound:
            return "Archive file not found"
        case .unsupportedFormat:
            return "Unsupported file format"
        case let .extractionFailed(message):
            return "Failed to extract archive: \(message)"
        case .invalidImageData:
            return "Invalid image data"
        case let .pageOutOfRange(page, total):
            return "Page \(page) is out of range (total: \(total))"
        }
    }
}
