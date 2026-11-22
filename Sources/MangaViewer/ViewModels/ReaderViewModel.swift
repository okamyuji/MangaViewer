import Foundation
import os.log
import SwiftData
import SwiftUI

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

    var spreadImages: (left: PlatformImage?, right: PlatformImage?) = (nil, nil)
    var isLoading: Bool = false
    @ObservationIgnored private var openRequestID = 0
    /// Runs once a book is on screen and before its pages open; tests hold an open here to act inside it.
    @ObservationIgnored var beforePagesOpen: @MainActor () async -> Void = {}
    /// Renders the error placeholder for a page; tests replace it to simulate a failed render.
    @ObservationIgnored var renderPlaceholder: @MainActor (AnyView) -> CGImage? = { view in
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        return renderer.cgImage
    }

    var errorMessage: String?
    var showBookmarkToast: Bool = false
    var bookmarkToastMessage: String = ""

    /// The book after this one in its folder, opened when reading goes past the last page.
    private(set) var nextVolume: Book?

    var canGoForward: Bool {
        currentPage < totalPages - 1 || nextVolume != nil
    }

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
    /// Set by the view when the reader area is portrait (iPad held upright)
    private(set) var prefersSinglePage: Bool = false

    private var provider: PageProvider?
    private let imageCache = ImageCache()
    private var modelContext: ModelContext?

    private var accessingURL: URL?
    private var loadingTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    private var volumeTask: Task<Void, Never>?

    init(settings: SettingsViewModel = SettingsViewModel()) {
        readingDirection = settings.readingDirection
        zoomMode = settings.zoomMode
    }

    func openBook(_ book: Book, modelContext: ModelContext, startPage: Int? = nil) async {
        openRequestID += 1
        let requestID = openRequestID
        loadingTask?.cancel()
        loadingTask = nil
        provider?.close()
        provider = nil
        nextVolume = nil
        // Holds page turns off until this book's pages are known; the previous book's count would let them through
        totalPages = 0

        if let previousURL = accessingURL {
            previousURL.stopAccessingSecurityScopedResource()
            accessingURL = nil
        }

        await imageCache.clear()
        guard isCurrentOpen(requestID) else { return }
        self.modelContext = modelContext
        currentBook = book
        currentPage = startPage ?? book.progress?.currentPage ?? 0
        isLoading = true
        errorMessage = nil
        await beforePagesOpen()
        guard isCurrentOpen(requestID) else { return }

        do {
            let (url, scopedURL) = try await resolveBookURL(book)
            guard isCurrentOpen(requestID) else {
                if let scopedURL {
                    await SecurityScopedBookmarkManager.shared.stopAccessing(url: scopedURL)
                }
                return
            }
            accessingURL = scopedURL

            // A coordinated read can wait for an iCloud download, so open the book off MainActor
            let opened = try await Task.detached { try ArchiveService.provider(for: url) }.value
            // The detached open ignores cancellation. A newer open or closeBook has already released
            // this request's access, so a stale result is only closed.
            guard isCurrentOpen(requestID) else {
                opened.close()
                return
            }
            provider = opened
            totalPages = provider?.pageCount ?? 0

            if totalPages == 0 {
                provider?.close()
                provider = nil
                errorMessage = "このファイルには表示可能なページがありません。"
                isLoading = false
                return
            }

            book.lastOpenedAt = Date()
            try? modelContext.save()
            nextVolume = findNextVolume()

            await loadCurrentPage()
        } catch {
            guard isCurrentOpen(requestID) else { return }
            if let url = accessingURL {
                accessingURL = nil
                await SecurityScopedBookmarkManager.shared.stopAccessing(url: url)
            }
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    /// False once a newer openBook, closeBook or cancellation has superseded the request.
    private func isCurrentOpen(_ requestID: Int) -> Bool {
        requestID == openRequestID && !Task.isCancelled
    }

    /// Returns the URL to read and, when a bookmark was resolved, the URL whose security scope is
    /// now held and must be released.
    private func resolveBookURL(_ book: Book) async throws -> (url: URL, scopedURL: URL?) {
        var url = URL(fileURLWithPath: book.filePath)
        var scopedURL: URL?

        if let bookmarkData = book.bookmarkData {
            guard let resolved = await SecurityScopedBookmarkManager.shared.resolveAndAccess(
                bookmarkData: bookmarkData
            ) else {
                logger.warning("Failed to resolve bookmark for \(book.filePath)")
                throw MangaViewerError.accessLost
            }
            scopedURL = resolved.url
            url = resolved.url
            if resolved.isStale {
                book.bookmarkData = resolved.bookmarkData
                if resolved.url.path != book.filePath {
                    book.filePath = resolved.url.path
                }
            }
        } else {
            do {
                book.bookmarkData = try url.bookmarkData(
                    options: BookmarkOptions.creation,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
            } catch {
                logger.info("Could not create bookmark for \(book.filePath): \(error)")
            }
        }

        return (url, scopedURL)
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
        openRequestID += 1
        loadingTask?.cancel()
        loadingTask = nil
        toastTask?.cancel()
        toastTask = nil
        volumeTask?.cancel()
        volumeTask = nil
        nextVolume = nil

        saveProgress()
        provider?.close()
        provider = nil
        currentBook = nil
        spreadImages = (nil, nil)
        isLoading = false

        let cache = imageCache
        let url = accessingURL
        accessingURL = nil

        Task {
            await cache.clear()
            if let url {
                await SecurityScopedBookmarkManager.shared.stopAccessing(url: url)
            }
        }
    }

    private var currentStep: Int {
        displaysSinglePage ? 1 : 2
    }

    func nextPage() {
        guard totalPages > 0 else { return }
        // Looked up again on the turn: the volume found at open may have been deleted from the library since
        if currentPage + currentStep >= totalPages, let modelContext {
            nextVolume = findNextVolume()
            if let next = nextVolume {
                volumeTask?.cancel()
                volumeTask = Task { await openBook(next, modelContext: modelContext, startPage: 0) }
                return
            }
        }
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
        guard totalPages > 0 else { return }
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

    func setPrefersSinglePage(_ single: Bool) {
        guard single != prefersSinglePage else { return }
        prefersSinglePage = single
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
        // A page whose placeholder failed to render left an error; this load sets it again if needed
        errorMessage = nil

        await loadSpreadImages()

        // If cancelled (replaced by a newer loadCurrentPage task), exit without
        // touching isLoading — the replacement task owns the flag now.
        guard !Task.isCancelled else { return }

        imageCache.prefetch(around: currentPage, totalPages: totalPages, using: provider)
        if currentPage + currentStep >= totalPages {
            // A volume imported into the folder while reading becomes reachable from the toolbar
            nextVolume = findNextVolume()
        }
        saveProgress()
        isLoading = false
    }

    private func loadImageForPage(_ index: Int) async -> PlatformImage? {
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

        let secondaryImage = prefersSinglePage ? nil : await loadImageForPage(currentPage + 1)
        guard !Task.isCancelled else { return }

        // If the secondary image is also wide, or there is no secondary page,
        // show only the primary page as a single page display
        if secondaryImage == nil || (secondaryImage.map { isLandscapeImage($0) } ?? false) {
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
}

extension ReaderViewModel {
    private func saveProgress() {
        guard let book = currentBook, totalPages > 0 else { return }

        if book.progress == nil {
            book.progress = ReadingProgress()
        }

        book.progress?.currentPage = currentPage
        book.progress?.updatedAt = Date()
        book.progress?.isCompleted = currentPage + currentStep >= totalPages

        try? modelContext?.save()
    }

    private func findNextVolume() -> Book? {
        guard let currentBook, let modelContext else { return nil }
        return Book.nextVolume(after: currentBook, in: (try? modelContext.fetch(FetchDescriptor<Book>())) ?? [])
    }

    private func isLandscapeImage(_ image: PlatformImage) -> Bool {
        let size = image.size
        return size.width > size.height * 1.2
    }

    private func createErrorPlaceholder(page: Int, error: Error) -> PlatformImage {
        let placeholder = VStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 80))
            Text("Page \(page + 1)\n\(error.localizedDescription)")
                .font(.system(size: 14))
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.secondary)
        .frame(width: 800, height: 1200)
        .background(Color.readerBackground)

        guard let cgImage = renderPlaceholder(AnyView(placeholder)) else {
            // Without a placeholder image the page would be blank; show the error as text instead
            errorMessage = "Page \(page + 1): \(error.localizedDescription)"
            return PlatformImage()
        }
        return PlatformImage.make(cgImage: cgImage)
    }

    private func applyFilters(to image: PlatformImage) -> PlatformImage {
        ImageFilterApplier.apply(filterSettings, to: image)
    }
}
