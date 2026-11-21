import Foundation

enum ImageFileFilter {
    static let supportedExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "webp", "bmp", "tiff", "tif"
    ]

    static func isImageFile(_ path: String) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        return supportedExtensions.contains(ext)
    }

    static func isImageFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return supportedExtensions.contains(ext)
    }

    /// An image-named entry is a page only when it resolves to a regular file: a folder named
    /// `cover.jpg`, a device such as /dev/zero, or a looped or broken link is not.
    static func isPageFile(_ url: URL) -> Bool {
        guard isImageFile(url) else { return false }
        let target = url.resolvingSymlinksInPath()
        return (try? target.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
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
