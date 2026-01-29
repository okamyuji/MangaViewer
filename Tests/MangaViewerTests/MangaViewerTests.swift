import Foundation
import SwiftUI
import Testing

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

@Suite("MangaViewerError Tests")
struct MangaViewerErrorTests {
    @Test("Error descriptions are provided")
    func errorDescriptions() {
        #expect(MangaViewerError.archiveNotFound.errorDescription != nil)
        #expect(MangaViewerError.unsupportedFormat.errorDescription != nil)
        #expect(MangaViewerError.extractionFailed("test").errorDescription?.contains("test") == true)
        #expect(MangaViewerError.invalidImageData.errorDescription != nil)
        #expect(MangaViewerError.pageOutOfRange(5, 10).errorDescription?.contains("5") == true)
    }
}

@Suite("DisplayMode Tests")
struct DisplayModeTests {
    @Test("DisplayMode has correct labels")
    func labels() {
        #expect(DisplayMode.single.label == "Single Page")
        #expect(DisplayMode.spread.label == "Spread (2 Pages)")
    }

    @Test("DisplayMode has correct icons")
    func icons() {
        #expect(DisplayMode.single.icon == "doc")
        #expect(DisplayMode.spread.icon == "doc.on.doc")
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

    @Test("Color returns nil for invalid hex")
    func colorFromInvalidHex() {
        let color = Color(hex: "invalid")
        #expect(color == nil)
    }
}
