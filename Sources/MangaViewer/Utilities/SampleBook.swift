#if DEBUG
    import CoreGraphics
    import Foundation
    import ImageIO
    import UniformTypeIdentifiers
    import ZIPFoundation

    /// Generates a small CBZ for tests and for the `-UITestSampleBook` launch argument.
    enum SampleBook {
        static let launchArgument = "-UITestSampleBook"
        /// Imports a sample book into the library instead of opening it, with page 3 a spread scan.
        static let libraryLaunchArgument = "-UITestLibrarySample"

        /// Pages in `widePages` are twice as wide as they are tall, like a scanned two-page spread.
        static func writeCBZ(
            to url: URL, pageCount: Int, pageWidth: Int = 600, pageHeight: Int = 900, widePages: Set<Int> = []
        ) throws {
            try? FileManager.default.removeItem(at: url)
            let archive = try Archive(url: url, accessMode: .create)
            for page in 0 ..< pageCount {
                let shade = CGFloat(page + 1) / CGFloat(pageCount + 1)
                let width = widePages.contains(page) ? pageHeight * 2 : pageWidth
                let png = try pngData(width: width, height: pageHeight, shade: shade)
                try archive.addEntry(
                    with: String(format: "page%03d.png", page + 1),
                    type: .file,
                    uncompressedSize: Int64(png.count)
                ) { position, size in
                    png.subdata(in: Int(position) ..< Int(position) + size)
                }
            }
        }

        private static func pngData(width: Int, height: Int, shade: CGFloat) throws -> Data {
            guard let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ) else { throw MangaViewerError.invalidImageData }
            context.setFillColor(CGColor(red: shade, green: 0.4, blue: 1 - shade, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))

            let data = NSMutableData()
            guard let image = context.makeImage(),
                  let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
            else { throw MangaViewerError.invalidImageData }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else { throw MangaViewerError.invalidImageData }
            return data as Data
        }
    }
#endif
