import Foundation

extension Book {
    /// The book after `current` in the same folder, ordered by file name the way Finder orders it (2 before 10).
    static func nextVolume(after current: Book, in library: [Book]) -> Book? {
        let currentURL = URL(fileURLWithPath: current.filePath)
        let folder = currentURL.deletingLastPathComponent().standardizedFileURL
        let siblings = library
            .filter { URL(fileURLWithPath: $0.filePath).deletingLastPathComponent().standardizedFileURL == folder }
            .sorted {
                let lhs = URL(fileURLWithPath: $0.filePath).lastPathComponent
                let rhs = URL(fileURLWithPath: $1.filePath).lastPathComponent
                return lhs.localizedStandardCompare(rhs) == .orderedAscending
            }
        guard let index = siblings.firstIndex(where: { $0 === current }), index + 1 < siblings.count else {
            return nil
        }
        return siblings[index + 1]
    }
}
