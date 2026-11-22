import Foundation

extension Book {
    /// The book after `current` in the same folder, ordered by file name the way Finder orders it (2 before 10).
    static func nextVolume(after current: Book, in library: [Book]) -> Book? {
        let currentURL = URL(fileURLWithPath: current.filePath)
        let folder = currentURL.deletingLastPathComponent().standardizedFileURL
        let name = currentURL.lastPathComponent
        return library
            .map { (book: $0, url: URL(fileURLWithPath: $0.filePath)) }
            .filter { $0.url.deletingLastPathComponent().standardizedFileURL == folder }
            .map { (book: $0.book, name: $0.url.lastPathComponent) }
            .filter { $0.name.localizedStandardCompare(name) == .orderedDescending }
            .min { $0.name.localizedStandardCompare($1.name) == .orderedAscending }?
            .book
    }
}
