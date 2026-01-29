import Foundation

enum ImageFileFilter {
    static let supportedExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "webp", "bmp", "tiff", "tif",
    ]

    static func isImageFile(_ path: String) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        return supportedExtensions.contains(ext)
    }

    static func isImageFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return supportedExtensions.contains(ext)
    }

    static func sortedNaturally(_ paths: [String]) -> [String] {
        paths.sorted { lhs, rhs in
            lhs.compare(rhs, options: [.numeric, .caseInsensitive]) == .orderedAscending
        }
    }

    static func sortedNaturally(_ urls: [URL]) -> [URL] {
        urls.sorted { lhs, rhs in
            lhs.lastPathComponent.compare(
                rhs.lastPathComponent,
                options: [.numeric, .caseInsensitive]
            ) == .orderedAscending
        }
    }
}
