import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import MangaViewer

enum TestImages {
    static func solidCGImage(width: Int, height: Int) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    static func solid(width: Int, height: Int) -> PlatformImage {
        PlatformImage.make(cgImage: solidCGImage(width: width, height: height))
    }

    static func pngData(width: Int, height: Int, dpi: Int = 72) -> Data {
        let data = NSMutableData()
        let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        let properties = [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi] as CFDictionary
        CGImageDestinationAddImage(dest, solidCGImage(width: width, height: height), properties)
        CGImageDestinationFinalize(dest)
        return data as Data
    }

    static func pixelSize(ofEncoded data: Data) -> CGSize? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return CGSize(width: image.width, height: image.height)
    }
}

@Suite("PlatformImage Tests")
struct PlatformImageTests {
    @Test("pixelSize reports the bitmap size of the backing CGImage")
    func pixelSizeMatchesBitmap() {
        let image = TestImages.solid(width: 400, height: 600)
        #expect(image.pixelSize == CGSize(width: 400, height: 600))
    }

    @Test("init(imageData:) decodes PNG data")
    func decodesPNG() throws {
        let image = try #require(PlatformImage(imageData: TestImages.pngData(width: 30, height: 20)))
        #expect(image.pixelSize == CGSize(width: 30, height: 20))
    }

    @Test("pixelSize counts bitmap pixels even when the file declares a high DPI")
    func pixelSizeIgnoresDPI() throws {
        let image = try #require(PlatformImage(imageData: TestImages.pngData(width: 40, height: 60, dpi: 144)))
        #expect(image.pixelSize == CGSize(width: 40, height: 60))
    }

    @Test("init(imageData:) returns nil for non-image data")
    func rejectsGarbage() {
        #expect(PlatformImage(imageData: Data("not an image".utf8)) == nil)
        #expect(PlatformImage(imageData: Data()) == nil)
    }

    @Test("cgImageValue exposes the pixels for Core Image")
    func cgImageValueAvailable() throws {
        let cgImage = try #require(TestImages.solid(width: 8, height: 4).cgImageValue)
        #expect(cgImage.width == 8)
        #expect(cgImage.height == 4)
    }
}

@Suite("ThumbnailGenerator Tests")
struct ThumbnailGeneratorTests {
    private let maxSize = CGSize(width: 200, height: 300)

    @Test("portrait page is scaled to fit and encoded as JPEG")
    func portraitFits() throws {
        let data = try #require(
            ThumbnailGenerator.jpegData(from: TestImages.solid(width: 400, height: 600), maxSize: maxSize)
        )
        #expect(data.prefix(2) == Data([0xFF, 0xD8]))
        #expect(TestImages.pixelSize(ofEncoded: data) == CGSize(width: 200, height: 300))
    }

    @Test("wide spread keeps its aspect ratio inside the box")
    func wideFits() throws {
        let data = try #require(
            ThumbnailGenerator.jpegData(from: TestImages.solid(width: 1000, height: 200), maxSize: maxSize)
        )
        #expect(TestImages.pixelSize(ofEncoded: data) == CGSize(width: 200, height: 40))
    }

    @Test("small page is scaled up to the box like the original macOS behavior")
    func smallScalesUp() throws {
        let data = try #require(
            ThumbnailGenerator.jpegData(from: TestImages.solid(width: 20, height: 30), maxSize: maxSize)
        )
        #expect(TestImages.pixelSize(ofEncoded: data) == CGSize(width: 200, height: 300))
    }

    @Test("generate(from:) encodes the first page of a book")
    func generateFromFirstPage() async throws {
        let data = try #require(await ThumbnailGenerator.generate(from: StubPageProvider(pageCount: 1)))
        #expect(TestImages.pixelSize(ofEncoded: data) == CGSize(width: 200, height: 300))
    }

    @Test("generate(from:) returns nil for a book without pages or with an unreadable first page")
    func generateWithoutUsablePage() async {
        #expect(await ThumbnailGenerator.generate(from: StubPageProvider(pageCount: 0)) == nil)
        #expect(await ThumbnailGenerator.generate(from: StubPageProvider(pageCount: 2, failingPages: [0])) == nil)
    }

    @Test("fractional target sizes are rounded to the nearest pixel")
    func fractionalSizeRounds() throws {
        let data = try #require(
            ThumbnailGenerator.jpegData(from: TestImages.solid(width: 333, height: 500), maxSize: maxSize)
        )
        #expect(TestImages.pixelSize(ofEncoded: data) == CGSize(width: 200, height: 300))
    }

    @Test("an extremely thin strip still produces a one-pixel-high thumbnail")
    func thinStripKeepsOnePixel() throws {
        let data = try #require(
            ThumbnailGenerator.jpegData(from: TestImages.solid(width: 3000, height: 1), maxSize: maxSize)
        )
        #expect(TestImages.pixelSize(ofEncoded: data) == CGSize(width: 200, height: 1))
    }
}

@Suite("FolderLoader Tests")
struct FolderLoaderTests {
    private func makeFolder(_ files: [String: Data]) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (name, data) in files {
            try data.write(to: folder.appendingPathComponent(name))
        }
        return folder
    }

    @Test("pages load in natural order with their decoded size")
    func loadsInNaturalOrder() async throws {
        let loader = try FolderLoader(url: makeFolder([
            "page10.png": TestImages.pngData(width: 30, height: 30),
            "page2.png": TestImages.pngData(width: 20, height: 20),
            "page1.png": TestImages.pngData(width: 10, height: 10)
        ]))
        #expect(loader.pageCount == 3)
        #expect(try await loader.image(at: 0).pixelSize == CGSize(width: 10, height: 10))
        #expect(try await loader.image(at: 2).pixelSize == CGSize(width: 30, height: 30))
    }

    @Test("a file with an image extension but broken contents throws invalidImageData")
    func brokenImageThrows() async throws {
        let loader = try FolderLoader(url: makeFolder(["page1.png": Data("broken".utf8)]))
        await #expect {
            _ = try await loader.image(at: 0)
        } throws: { error in
            if case MangaViewerError.invalidImageData = error {
                return true
            }
            return false
        }
    }

    @Test("an index past the last page throws pageOutOfRange")
    func outOfRangeThrows() async throws {
        let loader = try FolderLoader(url: makeFolder(["page1.png": TestImages.pngData(width: 4, height: 4)]))
        await #expect {
            _ = try await loader.image(at: 1)
        } throws: { error in
            if case MangaViewerError.pageOutOfRange(1, 1) = error {
                return true
            }
            return false
        }
    }
}
