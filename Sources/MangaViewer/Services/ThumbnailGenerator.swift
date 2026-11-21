import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ThumbnailGenerator {
    static func generate(
        from provider: PageProvider,
        size: CGSize = CGSize(width: Constants.Thumbnail.width, height: Constants.Thumbnail.height)
    ) async -> Data? {
        guard provider.pageCount > 0, let image = try? await provider.image(at: 0) else { return nil }
        return jpegData(from: image, maxSize: size)
    }

    /// Scales the image to fit `maxSize` (up or down, keeping aspect ratio) and encodes it as JPEG.
    static func jpegData(from image: PlatformImage, maxSize: CGSize) -> Data? {
        guard let source = image.cgImageValue, source.width > 0, source.height > 0 else { return nil }

        let ratio = min(maxSize.width / CGFloat(source.width), maxSize.height / CGFloat(source.height))
        let width = max(1, Int((CGFloat(source.width) * ratio).rounded()))
        let height = max(1, Int((CGFloat(source.height) * ratio).rounded()))

        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let scaled = context.makeImage() else { return nil }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }
        let options = [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary
        CGImageDestinationAddImage(destination, scaled, options)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
