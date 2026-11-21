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
            "Archive file not found"
        case .pageTooLarge:
            "This page is too large to open safely."
        case .accessLost:
            "Access to this book was lost. Add it to the library again."
        case .unsupportedFormat:
            "Unsupported file format"
        case let .extractionFailed(message):
            "Failed to extract archive: \(message)"
        case .invalidImageData:
            "Invalid image data"
        case let .pageOutOfRange(page, total):
            "Page \(page) is out of range (total: \(total))"
        }
    }
}
