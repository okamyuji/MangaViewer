import AppKit
import Foundation
import SwiftData

@Observable
@MainActor
final class LibraryViewModel {
    var searchText: String = ""
    var selectedTag: Tag?
    var sortOrder: SortOrder = .title
    var isImporting: Bool = false

    private let modelContext: ModelContext
    private let libraryWatcher = LibraryWatcher()

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        setupWatcher()
    }

    private func setupWatcher() {
        libraryWatcher.onFilesChanged = { [weak self] in
            Task { @MainActor in
                self?.refreshLibrary()
            }
        }
    }

    func addFolder(_ url: URL) async {
        isImporting = true
        defer { isImporting = false }

        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false

        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return
        }

        if isDirectory.boolValue {
            await scanFolder(url)
        } else {
            await addBook(at: url)
        }
    }

    private func scanFolder(_ folderURL: URL) async {
        let fileManager = FileManager.default
        guard
            let enumerator = fileManager.enumerator(
                at: folderURL,
                includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        else {
            return
        }

        let urls = enumerator.compactMap { $0 as? URL }
        for fileURL in urls where ArchiveService.bookType(for: fileURL) != nil {
            await addBook(at: fileURL)
        }

        libraryWatcher.watch(folder: folderURL)
    }

    private func addBook(at url: URL) async {
        let filePath = url.path

        do {
            let descriptor = FetchDescriptor<Book>()
            let allBooks = try modelContext.fetch(descriptor)
            let existingBook = allBooks.first { $0.filePath == filePath }
            if existingBook != nil {
                return
            }
        } catch {
            return
        }

        guard let bookType = ArchiveService.bookType(for: url) else {
            return
        }

        do {
            let provider = try ArchiveService.provider(for: url)
            defer { provider.close() }

            let title = url.deletingPathExtension().lastPathComponent
            let book = Book(
                title: title,
                filePath: url.path,
                type: bookType,
                totalPages: provider.pageCount
            )

            if let thumbnailData = await ThumbnailGenerator.generate(from: provider) {
                book.thumbnailData = thumbnailData
            }

            let progress = ReadingProgress()
            book.progress = progress

            modelContext.insert(book)
            try modelContext.save()
        } catch {
            print("Failed to add book: \(error)")
        }
    }

    func removeBook(_ book: Book) {
        modelContext.delete(book)
        try? modelContext.save()
    }

    func refreshLibrary() {
        try? modelContext.save()
    }

    func openBookInFinder(_ book: Book) {
        let url = URL(fileURLWithPath: book.filePath)
        NSWorkspace.shared.selectFile(
            url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path
        )
    }
}
