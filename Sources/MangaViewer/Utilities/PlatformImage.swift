import CoreGraphics
import Foundation
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

    convenience init?(imageData: Data) {
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
