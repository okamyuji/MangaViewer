import CoreGraphics
import Foundation
import ImageIO
import SwiftUI

#if os(macOS)
    import AppKit

    typealias PlatformImage = NSImage
#else
    import UIKit

    typealias PlatformImage = UIImage
#endif

extension PlatformImage {
    static func make(cgImage: CGImage) -> PlatformImage {
        #if os(macOS)
            NSImage(cgImage: cgImage, size: CGSize(width: cgImage.width, height: cgImage.height))
        #else
            UIImage(cgImage: cgImage)
        #endif
    }

    /// Keeps the original's point size (DPI on macOS, scale and orientation on iOS), which
    /// actualSize and custom zoom lay out by.
    static func make(cgImage: CGImage, matching original: PlatformImage) -> PlatformImage {
        #if os(macOS)
            NSImage(cgImage: cgImage, size: original.size)
        #else
            UIImage(cgImage: cgImage, scale: original.scale, orientation: original.imageOrientation)
        #endif
    }

    /// Images with more than `maxPixels` pixels are decoded downscaled, so a small file that
    /// declares huge dimensions cannot exhaust memory.
    convenience init?(imageData: Data, maxPixels: Int = Constants.Limits.maxImagePixels) {
        if let source = CGImageSourceCreateWithData(imageData as CFData, nil),
           let size = Self.declaredSize(source), size.width * size.height > maxPixels {
            // An oversized image that cannot be downscaled is refused, never decoded at full size
            guard let downscaled = Self.downscaledImage(source, size: size, maxPixels: maxPixels) else {
                return nil
            }
            #if os(macOS)
                self.init(cgImage: downscaled, size: CGSize(width: downscaled.width, height: downscaled.height))
            #else
                self.init(cgImage: downscaled, scale: 1, orientation: .up)
            #endif
            return
        }
        #if os(macOS)
            self.init(data: imageData)
        #else
            // UIImage keeps EXIF rotation in imageOrientation, which cgImage ignores; redraw upright
            // so thumbnails, filters and pixelSize see the page the way it is displayed.
            guard let decoded = UIImage(data: imageData) else { return nil }
            var upright = decoded.cgImage
            if decoded.imageOrientation != .up {
                let format = UIGraphicsImageRendererFormat()
                format.scale = decoded.scale
                upright = UIGraphicsImageRenderer(size: decoded.size, format: format)
                    .image { _ in decoded.draw(at: .zero) }.cgImage
            }
            guard let upright else { return nil }
            self.init(cgImage: upright, scale: decoded.scale, orientation: .up)
        #endif
    }

    private static func declaredSize(_ source: CGImageSource) -> (width: Int, height: Int)? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else {
            return nil
        }
        return (width, height)
    }

    private static func downscaledImage(
        _ source: CGImageSource, size: (width: Int, height: Int), maxPixels: Int
    ) -> CGImage? {
        let scale = (Double(maxPixels) / Double(size.width * size.height)).squareRoot()
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(Double(max(size.width, size.height)) * scale)
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    var cgImageValue: CGImage? {
        #if os(macOS)
            cgImage(forProposedRect: nil, context: nil, hints: nil)
        #else
            cgImage
        #endif
    }

    var pixelSize: CGSize {
        guard let cgImage = cgImageValue else { return size }
        return CGSize(width: cgImage.width, height: cgImage.height)
    }
}

extension Image {
    init(platformImage: PlatformImage) {
        #if os(macOS)
            self.init(nsImage: platformImage)
        #else
            self.init(uiImage: platformImage)
        #endif
    }
}

extension Color {
    static var readerBackground: Color {
        #if os(macOS)
            Color(nsColor: .windowBackgroundColor)
        #else
            Color(uiColor: .systemBackground)
        #endif
    }
}
