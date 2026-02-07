import AppKit
import Foundation
import os.log
import SwiftData

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "MangaViewer", category: "ReaderViewModel"
)

@Observable
@MainActor
final class ReaderViewModel {
    var currentBook: Book?
    var currentPage: Int = 0
    var totalPages: Int = 0
    var readingDirection: ReadingDirection = .rightToLeft
    var zoomMode: ZoomMode = .fitPage
    var zoomScale: CGFloat = 1.0
    var filterSettings: ImageFilterSettings = .default
    var isFullScreen: Bool = false

    var spreadImages: (left: NSImage?, right: NSImage?) = (nil, nil)
    var isLoading: Bool = false
    var errorMessage: String?
    var showBookmarkToast: Bool = false
    var bookmarkToastMessage: String = ""

    var canBookmark: Bool {
        currentBook != nil
    }

    var hasBookmarkOnCurrentPage: Bool {
        currentBook?.bookmarks.contains { $0.pageNumber == currentPage } ?? false
    }

    /// Whether the current spread display is showing a single wide (landscape) page
    private(set) var isCurrentPageWide: Bool = false
    /// Whether the display is showing a single page (wide primary or wide secondary)
    private var displaysSinglePage: Bool = false

    private var provider: PageProvider?
    private let imageCache = ImageCache()
    private var modelContext: ModelContext?

    private var accessingURL: URL?
    private var loadingTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?

    func openBook(_ book: Book, modelContext: ModelContext) async {
        loadingTask?.cancel()
        loadingTask = nil

        if let previousURL = accessingURL {
            previousURL.stopAccessingSecurityScopedResource()
            accessingURL = nil
        }

        imageCache.clear()
        self.modelContext = modelContext
        currentBook = book
        currentPage = book.progress?.currentPage ?? 0
        isLoading = true
        errorMessage = nil

        do {
            var url = URL(fileURLWithPath: book.filePath)

            if let bookmarkData = book.bookmarkData {
                if let resolved = await SecurityScopedBookmarkManager.shared.resolveAndAccess(
                    bookmarkData: bookmarkData
                ) {
                    accessingURL = resolved.url
                    url = resolved.url
                    if resolved.isStale {
                        book.bookmarkData = resolved.bookmarkData
                        if resolved.url.path != book.filePath {
                            book.filePath = resolved.url.path
                        }
                    }
                } else {
                    logger.warning("Failed to resolve bookmark for \(book.filePath)")
                    errorMessage = "ファイルへのアクセス権が失われました。再度ファイルをライブラリに追加してください。"
                    isLoading = false
                    return
                }
            }

            provider = try ArchiveService.provider(for: url)
            totalPages = provider?.pageCount ?? 0

            book.lastOpenedAt = Date()
            try? modelContext.save()

            await loadCurrentPage()
        } catch {
            if let url = accessingURL {
                url.stopAccessingSecurityScopedResource()
                accessingURL = nil
            }
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
        loadingTask?.cancel()
        loadingTask = nil
        toastTask?.cancel()
        toastTask = nil

        saveProgress()
        provider?.close()
        provider = nil
        currentBook = nil
        spreadImages = (nil, nil)
        imageCache.clear()

        if let url = accessingURL {
            url.stopAccessingSecurityScopedResource()
            accessingURL = nil
        }
    }

    private var currentStep: Int {
        displaysSinglePage ? 1 : 2
    }

    func nextPage() {
        guard totalPages > 0 else { return }
        let newPage = min(currentPage + currentStep, totalPages - 1)
        if newPage != currentPage {
            currentPage = newPage
            scheduleLoadPage()
        }
    }

    func previousPage() {
        guard totalPages > 0 else { return }
        let newPage = max(currentPage - currentStep, 0)
        if newPage != currentPage {
            currentPage = newPage
            scheduleLoadPage()
        }
    }

    func goToPage(_ page: Int) {
        let clampedPage = max(0, min(page, totalPages - 1))
        if clampedPage != currentPage {
            currentPage = clampedPage
            scheduleLoadPage()
        }
    }

    func setReadingDirection(_ direction: ReadingDirection) {
        guard direction != readingDirection else { return }
        readingDirection = direction
        scheduleLoadPage()
    }

    func applyCurrentFilters() {
        scheduleLoadPage()
    }

    private func scheduleLoadPage() {
        loadingTask?.cancel()
        loadingTask = Task { await loadCurrentPage() }
    }

    func toggleFullScreen() {
        isFullScreen.toggle()
    }

    var sortedBookmarks: [Bookmark] {
        currentBook?.bookmarks.sorted { $0.pageNumber < $1.pageNumber } ?? []
    }

    func toggleBookmark() {
        guard let book = currentBook else { return }

        if let existing = book.bookmarks.first(where: { $0.pageNumber == currentPage }) {
            removeBookmark(existing)
            showToast("Bookmark removed")
        } else {
            addBookmark()
            showToast("Bookmark added")
        }
    }

    func addBookmark(note: String? = nil) {
        guard let book = currentBook else { return }

        if book.bookmarks.contains(where: { $0.pageNumber == currentPage }) {
            return
        }

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

    func goToBookmark(_ bookmark: Bookmark) {
        goToPage(bookmark.pageNumber)
    }

    private func showToast(_ message: String) {
        toastTask?.cancel()
        bookmarkToastMessage = message
        showBookmarkToast = true
        toastTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            showBookmarkToast = false
        }
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
        defer { isLoading = false }

        await loadSpreadImages()

        guard !Task.isCancelled else { return }

        imageCache.prefetch(around: currentPage, totalPages: totalPages, using: provider)
        saveProgress()
    }

    private func isLandscapeImage(_ image: NSImage) -> Bool {
        let size = image.size
        return size.width > size.height * 1.2
    }

    private func loadImageForPage(_ index: Int) async -> NSImage? {
        guard let provider, index >= 0, index < totalPages else { return nil }
        if let cached = imageCache.image(for: index) {
            return cached
        }
        do {
            let image = try await provider.image(at: index)
            imageCache.set(image, for: index)
            return image
        } catch {
            logger.error("Failed to load page \(index): \(error.localizedDescription)")
            return createErrorPlaceholder(page: index, error: error)
        }
    }

    private func loadSpreadImages() async {
        guard provider != nil else { return }

        // Load the primary page first to check if it's a wide (spread scan) image
        let primaryImage = await loadImageForPage(currentPage)
        guard !Task.isCancelled else { return }

        if let primary = primaryImage, isLandscapeImage(primary) {
            // Wide image detected: show only this page across the full spread
            isCurrentPageWide = true
            displaysSinglePage = true
            let filtered = applyFilters(to: primary)
            spreadImages = (filtered, nil)
            return
        }

        isCurrentPageWide = false

        let secondaryIndex = currentPage + 1
        let secondaryImage = await loadImageForPage(secondaryIndex)
        guard !Task.isCancelled else { return }

        // If the secondary image is also wide, don't pair them
        if let secondary = secondaryImage, isLandscapeImage(secondary) {
            // Show only primary page; step by 1 so the wide secondary isn't skipped
            displaysSinglePage = true
            let filteredPrimary = primaryImage.map { applyFilters(to: $0) }
            if readingDirection == .rightToLeft {
                spreadImages = (nil, filteredPrimary)
            } else {
                spreadImages = (filteredPrimary, nil)
            }
            return
        }

        // Normal spread: two portrait pages side by side
        displaysSinglePage = false
        let filteredPrimary = primaryImage.map { applyFilters(to: $0) }
        let filteredSecondary = secondaryImage.map { applyFilters(to: $0) }

        if readingDirection == .rightToLeft {
            spreadImages = (filteredSecondary, filteredPrimary)
        } else {
            spreadImages = (filteredPrimary, filteredSecondary)
        }
    }

    private func createErrorPlaceholder(page: Int, error: Error) -> NSImage {
        let size = NSSize(width: 800, height: 1200)
        return NSImage(size: size, flipped: true) { drawRect in
            NSColor.windowBackgroundColor.setFill()
            NSBezierPath.fill(drawRect)

            let iconRect = NSRect(x: 350, y: 450, width: 100, height: 100)
            if let symbol = NSImage(
                systemSymbolName: "exclamationmark.triangle",
                accessibilityDescription: nil
            ) {
                symbol.draw(in: iconRect)
            }

            let style = NSMutableParagraphStyle()
            style.alignment = .center
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 14),
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: style
            ]
            let text = "Page \(page + 1)\n\(error.localizedDescription)"
            text.draw(in: NSRect(x: 50, y: 560, width: 700, height: 80), withAttributes: attrs)

            return true
        }
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
        book.progress?.isCompleted = currentPage + currentStep >= totalPages

        try? modelContext?.save()
    }
}
