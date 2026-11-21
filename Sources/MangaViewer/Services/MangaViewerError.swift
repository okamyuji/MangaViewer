import Foundation

enum MangaViewerError: LocalizedError {
    case archiveNotFound
    case accessLost
    case pageTooLarge
    case unsupportedFormat
    case extractionFailed(String)
    case invalidImageData
    case pageOutOfRange(Int, Int)

    var errorDescription: String? {
        switch self {
        case .archiveNotFound:
            return "Archive file not found"
        case .pageTooLarge:
            return "This page is too large to open safely."
        case .accessLost:
            return "Access to this book was lost. Add it to the library again."
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
