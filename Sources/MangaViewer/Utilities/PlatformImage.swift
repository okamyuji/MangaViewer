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

    convenience init?(imageData: Data) {
        self.init(data: imageData)
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
