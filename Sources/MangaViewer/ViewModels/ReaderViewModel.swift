import AppKit
import Foundation
import SwiftData

@Observable
@MainActor
final class ReaderViewModel {
    var currentBook: Book?
    var currentPage: Int = 0
    var totalPages: Int = 0
    var displayMode: DisplayMode = .spread
    var readingDirection: ReadingDirection = .rightToLeft
    var zoomMode: ZoomMode = .fitPage
    var zoomScale: CGFloat = 1.0
    var filterSettings: ImageFilterSettings = .default
    var isFullScreen: Bool = false

    var currentImage: NSImage?
    var spreadImages: (left: NSImage?, right: NSImage?) = (nil, nil)
    var isLoading: Bool = false
    var errorMessage: String?

    private var provider: PageProvider?
    private let imageCache = ImageCache()
    private var modelContext: ModelContext?

    private var accessingURL: URL?

    func openBook(_ book: Book, modelContext: ModelContext) async {
        if let previousURL = accessingURL {
            previousURL.stopAccessingSecurityScopedResource()
            accessingURL = nil
        }

        self.modelContext = modelContext
        currentBook = book
        currentPage = book.progress?.currentPage ?? 0
        isLoading = true
        errorMessage = nil

        do {
            var url = URL(fileURLWithPath: book.filePath)

            if let bookmarkData = book.bookmarkData {
                var isStale = false
                do {
                    let resolvedURL = try URL(
                        resolvingBookmarkData: bookmarkData,
                        options: .withSecurityScope,
                        relativeTo: nil,
                        bookmarkDataIsStale: &isStale
                    )
                    if resolvedURL.startAccessingSecurityScopedResource() {
                        accessingURL = resolvedURL
                    }
                    url = resolvedURL

                    if isStale {
                        do {
                            book.bookmarkData = try url.bookmarkData(
                                options: .withSecurityScope,
                                includingResourceValuesForKeys: nil,
                                relativeTo: nil
                            )
                        } catch {
                            print("Failed to refresh stale bookmark: \(error)")
                        }
                    }
                } catch {
                    print("Failed to resolve bookmark for \(book.filePath): \(error)")
                }
            }

            provider = try ArchiveService.provider(for: url)
            totalPages = provider?.pageCount ?? 0

            book.lastOpenedAt = Date()
            try? modelContext.save()

            await loadCurrentPage()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func openProvider(_ pageProvider: PageProvider, title _: String) async {
        provider = pageProvider
        currentPage = 0
        isLoading = true
        errorMessage = nil
        totalPages = pageProvider.pageCount

        await loadCurrentPage()

        isLoading = false
    }

    func closeBook() {
        saveProgress()
        provider?.close()
        provider = nil
        currentBook = nil
        currentImage = nil
        spreadImages = (nil, nil)
        imageCache.clear()

        if let url = accessingURL {
            url.stopAccessingSecurityScopedResource()
            accessingURL = nil
        }
    }

    func nextPage() {
        let step = displayMode == .spread ? 2 : 1
        let newPage = min(currentPage + step, totalPages - 1)
        if newPage != currentPage {
            currentPage = newPage
            Task { await loadCurrentPage() }
        }
    }

    func previousPage() {
        let step = displayMode == .spread ? 2 : 1
        let newPage = max(currentPage - step, 0)
        if newPage != currentPage {
            currentPage = newPage
            Task { await loadCurrentPage() }
        }
    }

    func goToPage(_ page: Int) {
        let clampedPage = max(0, min(page, totalPages - 1))
        if clampedPage != currentPage {
            currentPage = clampedPage
            Task { await loadCurrentPage() }
        }
    }

    func toggleDisplayMode() {
        displayMode = displayMode == .single ? .spread : .single
        Task { await loadCurrentPage() }
    }

    func toggleFullScreen() {
        isFullScreen.toggle()
    }

    func addBookmark(note: String? = nil) {
        guard let book = currentBook else { return }

        let bookmark = Bookmark(pageNumber: currentPage, note: note)
        book.bookmarks.append(bookmark)
        try? modelContext?.save()
    }

    func removeBookmark(_ bookmark: Bookmark) {
        guard let book = currentBook,
              let index = book.bookmarks.firstIndex(where: { $0.id == bookmark.id })
        else {
            return
        }
        book.bookmarks.remove(at: index)
        try? modelContext?.save()
    }

    func zoomIn() {
        zoomScale = min(zoomScale * 1.25, 5.0)
        zoomMode = .custom
    }

    func zoomOut() {
        zoomScale = max(zoomScale / 1.25, 0.25)
        zoomMode = .custom
    }

    func resetZoom() {
        zoomScale = 1.0
        zoomMode = .fitPage
    }

    private func loadCurrentPage() async {
        guard let provider else { return }

        isLoading = true

        if displayMode == .spread {
            await loadSpreadImages()
        } else {
            await loadSingleImage()
        }

        imageCache.prefetch(around: currentPage, totalPages: totalPages, using: provider)
        saveProgress()

        isLoading = false
    }

    private func loadSingleImage() async {
        guard let provider else { return }

        do {
            if let cached = imageCache.image(for: currentPage) {
                currentImage = applyFilters(to: cached)
            } else {
                let image = try await provider.image(at: currentPage)
                imageCache.set(image, for: currentPage)
                currentImage = applyFilters(to: image)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadSpreadImages() async {
        guard let provider else { return }

        // For RTL (manga style): right side shows odd pages, left side shows even pages
        // Page 0 (first page) should be on the right only
        // Pages 1-2 should be: right=1, left=2
        // Pages 3-4 should be: right=3, left=4
        // etc.

        let rightIndex: Int
        let leftIndex: Int

        if readingDirection == .rightToLeft {
            // Right side: current page (odd/first position)
            // Left side: next page (even position)
            rightIndex = currentPage
            leftIndex = currentPage + 1
        } else {
            // LTR: left side is current, right is next
            leftIndex = currentPage
            rightIndex = currentPage + 1
        }

        var leftImage: NSImage?
        var rightImage: NSImage?

        do {
            // Load right image (primary page in RTL)
            if rightIndex >= 0, rightIndex < totalPages {
                if let cached = imageCache.image(for: rightIndex) {
                    rightImage = applyFilters(to: cached)
                } else {
                    let image = try await provider.image(at: rightIndex)
                    imageCache.set(image, for: rightIndex)
                    rightImage = applyFilters(to: image)
                }
            }

            // Load left image (secondary page in RTL)
            if leftIndex >= 0, leftIndex < totalPages {
                if let cached = imageCache.image(for: leftIndex) {
                    leftImage = applyFilters(to: cached)
                } else {
                    let image = try await provider.image(at: leftIndex)
                    imageCache.set(image, for: leftIndex)
                    leftImage = applyFilters(to: image)
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        spreadImages = (leftImage, rightImage)
    }

    private func applyFilters(to image: NSImage) -> NSImage {
        ImageFilterApplier.apply(filterSettings, to: image)
    }

    private func saveProgress() {
        guard let book = currentBook else { return }

        if book.progress == nil {
            book.progress = ReadingProgress()
        }

        book.progress?.currentPage = currentPage
        book.progress?.updatedAt = Date()
        book.progress?.isCompleted = currentPage >= totalPages - 1

        try? modelContext?.save()
    }
}
