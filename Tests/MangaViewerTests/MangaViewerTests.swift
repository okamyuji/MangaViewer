import Foundation
import SwiftUI
import Testing
import ZIPFoundation
@testable import MangaViewer

@Suite("ImageFileFilter Tests")
struct ImageFileFilterTests {
    @Test("isImageFile returns true for supported extensions")
    func isImageFileSupported() {
        #expect(ImageFileFilter.isImageFile("test.jpg"))
        #expect(ImageFileFilter.isImageFile("test.jpeg"))
        #expect(ImageFileFilter.isImageFile("test.png"))
        #expect(ImageFileFilter.isImageFile("test.gif"))
        #expect(ImageFileFilter.isImageFile("test.webp"))
        #expect(ImageFileFilter.isImageFile("test.bmp"))
        #expect(ImageFileFilter.isImageFile("test.tiff"))
        #expect(ImageFileFilter.isImageFile("test.JPG"))
        #expect(ImageFileFilter.isImageFile("test.PNG"))
    }

    @Test("isImageFile returns false for unsupported extensions")
    func isImageFileUnsupported() {
        #expect(!ImageFileFilter.isImageFile("test.txt"))
        #expect(!ImageFileFilter.isImageFile("test.pdf"))
        #expect(!ImageFileFilter.isImageFile("test.zip"))
        #expect(!ImageFileFilter.isImageFile("test"))
    }

    @Test("sortedNaturally sorts strings in natural order")
    func sortedNaturallyStrings() {
        let input = ["page10.jpg", "page2.jpg", "page1.jpg", "page20.jpg"]
        let expected = ["page1.jpg", "page2.jpg", "page10.jpg", "page20.jpg"]
        let result = ImageFileFilter.sortedNaturally(input)
        #expect(result == expected)
    }

    @Test("sortedNaturally handles mixed case")
    func sortedNaturallyMixedCase() {
        let input = ["Page10.jpg", "page2.jpg", "PAGE1.jpg"]
        let result = ImageFileFilter.sortedNaturally(input)
        #expect(result[0].lowercased().contains("1"))
        #expect(result[1].lowercased().contains("2"))
        #expect(result[2].lowercased().contains("10"))
    }
}

@Suite("BookType Tests")
struct BookTypeTests {
    @Test("BookType raw values are correct")
    func rawValues() {
        #expect(BookType.cbz.rawValue == "cbz")
        #expect(BookType.cbr.rawValue == "cbr")
        #expect(BookType.folder.rawValue == "folder")
    }

    @Test("BookType is Codable")
    func codable() throws {
        let original = BookType.cbz
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(BookType.self, from: data)
        #expect(decoded == original)
    }
}

@Suite("ArchiveService Tests")
struct ArchiveServiceTests {
    @Test("bookType returns correct type for CBZ")
    func bookTypeCBZ() {
        let url = URL(fileURLWithPath: "/test/manga.cbz")
        #expect(ArchiveService.bookType(for: url) == .cbz)
    }

    @Test("bookType returns correct type for ZIP")
    func bookTypeZIP() {
        let url = URL(fileURLWithPath: "/test/manga.zip")
        #expect(ArchiveService.bookType(for: url) == .cbz)
    }

    @Test("bookType returns correct type for CBR")
    func bookTypeCBR() {
        let url = URL(fileURLWithPath: "/test/manga.cbr")
        #expect(ArchiveService.bookType(for: url) == .cbr)
    }

    @Test("bookType returns correct type for RAR")
    func bookTypeRAR() {
        let url = URL(fileURLWithPath: "/test/manga.rar")
        #expect(ArchiveService.bookType(for: url) == .cbr)
    }

    @Test("bookType returns nil for unsupported format")
    func bookTypeUnsupported() {
        let url = URL(fileURLWithPath: "/test/document.pdf")
        #expect(ArchiveService.bookType(for: url) == nil)
    }
}

@Suite("ZipExtractor Tests")
struct ZipExtractorTests {
    @Test("an archive that stores the same page path twice opens instead of crashing")
    func duplicateEntryPaths() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).cbz")
        let png = TestImages.pngData(width: 4, height: 6)
        let archive = try Archive(url: url, accessMode: .create)
        for _ in 0 ..< 2 {
            try archive.addEntry(with: "001.png", type: .file, uncompressedSize: Int64(png.count)) { position, size in
                png.subdata(in: Int(position) ..< Int(position) + size)
            }
        }

        defer { try? FileManager.default.removeItem(at: url) }

        let extractor = try ZipExtractor(url: url)

        #expect(extractor.pageCount == 1)
        #expect(try await extractor.image(at: 0).pixelSize == CGSize(width: 4, height: 6))
    }
}

@Suite("Decompression bomb Tests")
struct DecompressionBombTests {
    private static let limit: Int64 = 1024 * 1024

    /// A zip whose single page inflates to 4 MB of zeros from a few kilobytes.
    private func makeBomb() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).cbz")
        let size = 4 * 1024 * 1024
        let archive = try Archive(url: url, accessMode: .create)
        try archive.addEntry(
            with: "001.png", type: .file, uncompressedSize: Int64(size), compressionMethod: .deflate
        ) { _, chunk in
            Data(count: chunk)
        }
        return url
    }

    private func isPageTooLarge(_ error: any Error) -> Bool {
        if case MangaViewerError.pageTooLarge = error {
            return true
        }
        return false
    }

    @Test("a zip page that declares more than the limit is refused before it is inflated")
    func declaredSizeOverLimit() async throws {
        let url = try makeBomb()
        defer { try? FileManager.default.removeItem(at: url) }
        let extractor = try ZipExtractor(url: url, maxEntryBytes: Self.limit)

        await #expect { _ = try await extractor.image(at: 0) } throws: { isPageTooLarge($0) }
    }

    @Test("a zip page that lies about its size is stopped once it inflates past the limit")
    func understatedSizeStopsWhileInflating() async throws {
        let url = try makeBomb()
        defer { try? FileManager.default.removeItem(at: url) }
        var bytes = try Data(contentsOf: url)
        // Rewrite the uncompressed size in the local and central headers to 100 bytes
        func patch(signature: [UInt8], sizeOffset: Int) throws {
            let at = try #require(bytes.firstRange(of: Data(signature))).lowerBound + sizeOffset
            bytes.replaceSubrange(at ..< at + 4, with: [100, 0, 0, 0])
        }
        try patch(signature: [0x50, 0x4B, 0x03, 0x04], sizeOffset: 22)
        try patch(signature: [0x50, 0x4B, 0x01, 0x02], sizeOffset: 24)
        try bytes.write(to: url)
        let extractor = try ZipExtractor(url: url, maxEntryBytes: Self.limit)

        await #expect { _ = try await extractor.image(at: 0) } throws: { isPageTooLarge($0) }
    }

    @Test("a zip64 size beyond Int64 is refused instead of crashing the app")
    func zip64SizeBeyondInt64() async throws {
        let url = try makeBomb()
        defer { try? FileManager.default.removeItem(at: url) }
        var bytes = try Data(contentsOf: url)
        func readUInt16(_ at: Int) -> Int {
            Int(bytes[at]) | Int(bytes[at + 1]) << 8
        }
        let central = try #require(bytes.firstRange(of: Data([0x50, 0x4B, 0x01, 0x02]))).lowerBound
        let extraEnd = central + 46 + readUInt16(central + 28) + readUInt16(central + 30)
        // A zip64 extra field (ID 1) carrying an uncompressed size of 2^64 - 1
        let zip64Field: [UInt8] = [0x01, 0x00, 0x08, 0x00] + [UInt8](repeating: 0xFF, count: 8)
        bytes.insert(contentsOf: zip64Field, at: extraEnd)
        bytes.replaceSubrange(central + 24 ..< central + 28, with: [0xFF, 0xFF, 0xFF, 0xFF])
        let extraLength = readUInt16(central + 30) + zip64Field.count
        bytes.replaceSubrange(central + 30 ..< central + 32, with: [UInt8(extraLength & 0xFF), UInt8(extraLength >> 8)])
        let end = try #require(bytes.lastRange(of: Data([0x50, 0x4B, 0x05, 0x06]))).lowerBound
        let directorySize = readUInt16(end + 12) + zip64Field.count
        bytes.replaceSubrange(end + 12 ..< end + 14, with: [UInt8(directorySize & 0xFF), UInt8(directorySize >> 8)])
        try bytes.write(to: url)
        let extractor = try ZipExtractor(url: url, maxEntryBytes: Self.limit)

        await #expect { _ = try await extractor.image(at: 0) } throws: { isPageTooLarge($0) }
    }

    private static let page = TestImages.pngData(width: 6, height: 9)

    private func temporaryURL(_ suffix: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + suffix)
    }

    @Test("a zip page exactly at the limit opens, one byte over is refused")
    func zipLimitBoundary() async throws {
        let url = temporaryURL(".cbz")
        defer { try? FileManager.default.removeItem(at: url) }
        let archive = try Archive(url: url, accessMode: .create)
        try archive.addEntry(
            with: "001.png", type: .file, uncompressedSize: Int64(Self.page.count), compressionMethod: .deflate
        ) { position, size in
            Self.page.subdata(in: Int(position) ..< Int(position) + size)
        }
        let size = Int64(Self.page.count)

        _ = try await ZipExtractor(url: url, maxEntryBytes: size).image(at: 0)
        let tooSmall = try ZipExtractor(url: url, maxEntryBytes: size - 1)
        await #expect { _ = try await tooSmall.image(at: 0) } throws: { isPageTooLarge($0) }
    }

    /// A RAR 4 archive holding one stored (uncompressed) file; no tool here can write RAR.
    private func makeStoredRAR(name: String, contents: Data) -> Data {
        func crc32(_ bytes: [UInt8]) -> UInt32 {
            var crc: UInt32 = 0xFFFF_FFFF
            for byte in bytes {
                crc ^= UInt32(byte)
                for _ in 0 ..< 8 {
                    crc = (crc >> 1) ^ (0xEDB8_8320 & (0 &- (crc & 1)))
                }
            }
            return ~crc
        }
        func le<T: FixedWidthInteger>(_ value: T) -> [UInt8] {
            withUnsafeBytes(of: value.littleEndian, Array.init)
        }
        func block(type: UInt8, flags: UInt16, body: [UInt8]) -> [UInt8] {
            let rest = [type] + le(flags) + le(UInt16(7 + body.count)) + body
            return le(UInt16(truncatingIfNeeded: crc32(rest))) + rest
        }
        let nameBytes = Array(name.utf8)
        let size = le(UInt32(contents.count))
        // pack size, unpacked size, host OS, CRC, time, version 2.0, method "store", name length, attributes
        let fileHeader = size + size + [2] + le(crc32(Array(contents))) + le(UInt32(0x2100_0000)) + [20, 0x30]
            + le(UInt16(nameBytes.count)) + le(UInt32(0x20)) + nameBytes
        let marker: [UInt8] = [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00]
        return Data(
            marker + block(type: 0x73, flags: 0, body: [UInt8](repeating: 0, count: 6))
                + block(type: 0x74, flags: 0x8000, body: fileHeader) + Array(contents)
                + block(type: 0x7B, flags: 0x4000, body: [])
        )
    }

    @Test("a rar page exactly at the limit opens, one byte over is refused")
    func rarLimitBoundary() async throws {
        let url = temporaryURL(".cbr")
        defer { try? FileManager.default.removeItem(at: url) }
        try makeStoredRAR(name: "001.png", contents: Self.page).write(to: url)
        let size = Int64(Self.page.count)

        _ = try await RarExtractor(url: url, maxEntryBytes: size).image(at: 0)
        let tooSmall = try RarExtractor(url: url, maxEntryBytes: size - 1)
        await #expect { _ = try await tooSmall.image(at: 0) } throws: { isPageTooLarge($0) }
    }

    @Test("an image file in a folder exactly at the limit opens, one byte over is refused")
    func folderLimitBoundary() async throws {
        let folder = temporaryURL("")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Self.page.write(to: folder.appendingPathComponent("001.png"))
        let size = Int64(Self.page.count)

        _ = try await FolderLoader(url: folder, maxPageBytes: size).image(at: 0)
        let tooSmall = try FolderLoader(url: folder, maxPageBytes: size - 1)
        await #expect { _ = try await tooSmall.image(at: 0) } throws: { isPageTooLarge($0) }
    }

    @Test("an image with more pixels than the limit is decoded downscaled, keeping its shape")
    func hugeImageIsDownscaled() throws {
        let data = TestImages.pngData(width: 3000, height: 1500)

        let image = try #require(PlatformImage(imageData: data, maxPixels: 1_000_000))

        #expect(image.pixelSize.width * image.pixelSize.height <= 1_000_000)
        #expect(image.pixelSize.width == image.pixelSize.height * 2)
    }

    @Test("an image within the limit keeps its full size")
    func normalImageKeepsSize() throws {
        let image = try #require(PlatformImage(imageData: TestImages.pngData(width: 300, height: 450), maxPixels: 1_000_000))
        #expect(image.pixelSize == CGSize(width: 300, height: 450))
    }
}

@Suite("MangaViewerError Tests")
struct MangaViewerErrorTests {
    @Test("Error descriptions are provided")
    func errorDescriptions() {
        #expect(MangaViewerError.archiveNotFound.errorDescription != nil)
        #expect(MangaViewerError.accessLost.errorDescription?.contains("Add it to the library again") == true)
        #expect(MangaViewerError.unsupportedFormat.errorDescription != nil)
        #expect(MangaViewerError.extractionFailed("test").errorDescription?.contains("test") == true)
        #expect(MangaViewerError.invalidImageData.errorDescription != nil)
        #expect(MangaViewerError.pageOutOfRange(5, 10).errorDescription?.contains("5") == true)
    }
}

@Suite("ReadingDirection Tests")
struct ReadingDirectionTests {
    @Test("ReadingDirection has correct labels")
    func labels() {
        #expect(ReadingDirection.leftToRight.label == "Left to Right")
        #expect(ReadingDirection.rightToLeft.label == "Right to Left (Manga)")
    }
}

@Suite("ZoomMode Tests")
struct ZoomModeTests {
    @Test("ZoomMode has all expected cases")
    func allCases() {
        let cases = ZoomMode.allCases
        #expect(cases.contains(.fitPage))
        #expect(cases.contains(.fitWidth))
        #expect(cases.contains(.fitHeight))
        #expect(cases.contains(.actualSize))
        #expect(cases.contains(.custom))
    }
}

@Suite("SortOrder Tests")
struct SortOrderTests {
    @Test("SortOrder has correct labels")
    func labels() {
        #expect(SortOrder.title.label == "Title")
        #expect(SortOrder.dateAdded.label == "Date Added")
        #expect(SortOrder.lastOpened.label == "Last Opened")
    }
}

@Suite("ImageFilterSettings Tests")
struct ImageFilterSettingsTests {
    @Test("Default settings are correct")
    func defaultSettings() {
        let settings = ImageFilterSettings.default
        #expect(settings.brightness == 0)
        #expect(settings.contrast == 1)
        #expect(settings.sepia == 0)
        #expect(settings.grayscale == false)
    }

    @Test("isDefault returns true for default settings")
    func isDefaultTrue() {
        let settings = ImageFilterSettings()
        #expect(settings.isDefault)
    }

    @Test("isDefault returns false for modified settings")
    func isDefaultFalse() {
        var settings = ImageFilterSettings()
        settings.brightness = 0.5
        #expect(!settings.isDefault)
    }

    @Test("isDefault detects each modified property")
    func isDefaultEachProperty() {
        var s1 = ImageFilterSettings()
        s1.contrast = 1.5
        #expect(!s1.isDefault)

        var s2 = ImageFilterSettings()
        s2.sepia = 0.3
        #expect(!s2.isDefault)

        var s3 = ImageFilterSettings()
        s3.grayscale = true
        #expect(!s3.isDefault)
    }
}

@Suite("ImageFilterApplier Tests")
@MainActor
struct ImageFilterApplierTests {
    private func createTestImage() -> PlatformImage {
        TestImages.solid(width: 100, height: 100)
    }

    @Test("Default settings return original image unchanged")
    func defaultSettingsReturnOriginal() {
        let original = createTestImage()
        let result = ImageFilterApplier.apply(.default, to: original)
        #expect(result === original)
    }

    @Test("Non-default brightness produces different image")
    func brightnessApplied() {
        let original = createTestImage()
        var settings = ImageFilterSettings()
        settings.brightness = 0.5
        let result = ImageFilterApplier.apply(settings, to: original)
        #expect(result !== original)
        #expect(result.size == original.size)
    }

    @Test("Grayscale filter produces different image")
    func grayscaleApplied() {
        let original = createTestImage()
        var settings = ImageFilterSettings()
        settings.grayscale = true
        let result = ImageFilterApplier.apply(settings, to: original)
        #expect(result !== original)
        #expect(result.size == original.size)
    }

    @Test("Sepia filter produces different image")
    func sepiaApplied() {
        let original = createTestImage()
        var settings = ImageFilterSettings()
        settings.sepia = 0.8
        let result = ImageFilterApplier.apply(settings, to: original)
        #expect(result !== original)
        #expect(result.size == original.size)
    }

    @Test("Contrast filter produces different image")
    func contrastApplied() {
        let original = createTestImage()
        var settings = ImageFilterSettings()
        settings.contrast = 2.0
        let result = ImageFilterApplier.apply(settings, to: original)
        #expect(result !== original)
        #expect(result.size == original.size)
    }

    @Test("filtered image keeps the point size of a high-density original")
    func filterKeepsPointSize() {
        let pixels = TestImages.solidCGImage(width: 100, height: 100)
        #if os(macOS)
            let original = NSImage(cgImage: pixels, size: CGSize(width: 50, height: 50))
        #else
            let original = UIImage(cgImage: pixels, scale: 2, orientation: .up)
        #endif
        var settings = ImageFilterSettings()
        settings.sepia = 0.8

        let result = ImageFilterApplier.apply(settings, to: original)

        #expect(result.size == CGSize(width: 50, height: 50))
        #expect(result.pixelSize == CGSize(width: 100, height: 100))
    }
}

@Suite("ReaderViewModel Tests")
struct ReaderViewModelTests {
    @Test("setReadingDirection changes direction")
    @MainActor
    func setReadingDirection() {
        let vm = makeIsolatedReader()
        #expect(vm.readingDirection == .rightToLeft)

        vm.setReadingDirection(.leftToRight)
        #expect(vm.readingDirection == .leftToRight)

        vm.setReadingDirection(.rightToLeft)
        #expect(vm.readingDirection == .rightToLeft)
    }

    @Test("setReadingDirection does not change if same direction")
    @MainActor
    func setReadingDirectionSame() {
        let vm = makeIsolatedReader()
        vm.setReadingDirection(.rightToLeft)
        #expect(vm.readingDirection == .rightToLeft)
    }

    @Test("canBookmark is false when currentBook is nil")
    @MainActor
    func canBookmarkWithoutBook() {
        let vm = makeIsolatedReader()
        #expect(vm.canBookmark == false)
    }

    @Test("hasBookmarkOnCurrentPage is false when currentBook is nil")
    @MainActor
    func hasBookmarkWithoutBook() {
        let vm = makeIsolatedReader()
        #expect(vm.hasBookmarkOnCurrentPage == false)
    }

    @Test("addBookmark does nothing when currentBook is nil")
    @MainActor
    func addBookmarkWithoutBook() {
        let vm = makeIsolatedReader()
        vm.addBookmark()
        #expect(vm.showBookmarkToast == false)
    }

    @Test("toggleBookmark does nothing when currentBook is nil")
    @MainActor
    func toggleBookmarkWithoutBook() {
        let vm = makeIsolatedReader()
        vm.toggleBookmark()
        #expect(vm.showBookmarkToast == false)
    }

    @Test("sortedBookmarks is empty when currentBook is nil")
    @MainActor
    func sortedBookmarksWithoutBook() {
        let vm = makeIsolatedReader()
        #expect(vm.sortedBookmarks.isEmpty)
    }

    @Test("page navigation respects bounds")
    @MainActor
    func pageNavigationBounds() {
        let vm = makeIsolatedReader()
        vm.totalPages = 5
        vm.currentPage = 0

        vm.previousPage()
        #expect(vm.currentPage == 0)

        vm.goToPage(10)
        #expect(vm.currentPage == 4)

        vm.goToPage(-1)
        #expect(vm.currentPage == 0)
    }

    @Test("zoom in and out change scale")
    @MainActor
    func zoomInOut() {
        let vm = makeIsolatedReader()
        let initialScale = vm.zoomScale

        vm.zoomIn()
        #expect(vm.zoomScale > initialScale)
        #expect(vm.zoomMode == .custom)

        vm.resetZoom()
        #expect(vm.zoomScale == 1.0)
        #expect(vm.zoomMode == .fitPage)

        vm.zoomOut()
        #expect(vm.zoomScale < 1.0)
    }

    @Test("isCurrentPageWide defaults to false")
    @MainActor
    func isCurrentPageWideDefault() {
        let vm = makeIsolatedReader()
        #expect(vm.isCurrentPageWide == false)
    }
}

@Suite("Color Extension Tests")
struct ColorExtensionTests {
    @Test("Color initializes from valid hex")
    func colorFromHex() {
        let color = Color(hex: "#FF0000")
        #expect(color != nil)
    }

    @Test("Color initializes from hex without hash")
    func colorFromHexNoHash() {
        let color = Color(hex: "00FF00")
        #expect(color != nil)
    }

    @Test("toHex round-trips a color created from hex")
    func toHexRoundTrip() throws {
        let color = try #require(Color(hex: "#FF8000"))
        #expect(color.toHex() == "#FF8000")
    }

    @Test("toHex round-trips every 8-bit channel value")
    func toHexRoundTripsEveryChannelValue() {
        for value in 0 ... 255 {
            let hex = String(format: "#%02X%02X%02X", value, 255 - value, value / 2)
            #expect(Color(hex: hex)?.toHex() == hex)
        }
    }

    @Test("toHex writes black and white with two digits per channel")
    func toHexExtremes() {
        #expect(Color(hex: "000000")?.toHex() == "#000000")
        #expect(Color(hex: "FFFFFF")?.toHex() == "#FFFFFF")
    }

    @Test("Color returns nil for invalid hex")
    func colorFromInvalidHex() {
        let color = Color(hex: "invalid")
        #expect(color == nil)
    }
}
