import Foundation
import Testing
import ZIPFoundation
@testable import MangaViewer

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
        func le(_ value: some FixedWidthInteger) -> [UInt8] {
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

    @Test("a symlinked image in a folder is measured at its target, so a link cannot dodge the limit")
    func folderSymlinkIsMeasuredAtTarget() async throws {
        let root = temporaryURL("")
        let folder = root.appendingPathComponent("book")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("target.png")
        try Self.page.write(to: target)
        try FileManager.default.createSymbolicLink(
            at: folder.appendingPathComponent("001.png"), withDestinationURL: target
        )
        let loader = try FolderLoader(url: folder, maxPageBytes: Int64(Self.page.count) - 1)

        await #expect { _ = try await loader.image(at: 0) } throws: { isPageTooLarge($0) }
    }

    @Test("a folder page that links to a device or another non-file is not listed, so it is never read")
    func folderSkipsNonRegularFiles() throws {
        let folder = temporaryURL("")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Self.page.write(to: folder.appendingPathComponent("001.png"))
        try FileManager.default.createSymbolicLink(
            at: folder.appendingPathComponent("002.png"), withDestinationURL: URL(fileURLWithPath: "/dev/zero")
        )
        try FileManager.default.createSymbolicLink(
            at: folder.appendingPathComponent("003.png"), withDestinationURL: folder.appendingPathComponent("004.png")
        )
        try FileManager.default.createSymbolicLink(
            at: folder.appendingPathComponent("004.png"), withDestinationURL: folder.appendingPathComponent("003.png")
        )

        #expect(try FolderLoader(url: folder).pageCount == 1)
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
        let data = TestImages.pngData(width: 300, height: 450)
        let image = try #require(PlatformImage(imageData: data, maxPixels: 1_000_000))
        #expect(image.pixelSize == CGSize(width: 300, height: 450))
    }
}
