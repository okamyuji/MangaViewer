import AppKit
import Foundation

enum ThumbnailGenerator {
    static func generate(from provider: PageProvider, size: NSSize = NSSize(width: 200, height: 300)) async -> Data? {
        guard provider.pageCount > 0 else { return nil }

        do {
            let image = try await provider.image(at: 0)
            let thumbnail = resize(image: image, to: size)
            return thumbnail.tiffRepresentation.flatMap {
                NSBitmapImageRep(data: $0)?.representation(
                    using: .jpeg, properties: [.compressionFactor: 0.8]
                )
            }
        } catch {
            return nil
        }
    }

    private static func resize(image: NSImage, to targetSize: NSSize) -> NSImage {
        let imageSize = image.size
        let widthRatio = targetSize.width / imageSize.width
        let heightRatio = targetSize.height / imageSize.height
        let ratio = min(widthRatio, heightRatio)

        let newSize = NSSize(
            width: imageSize.width * ratio,
            height: imageSize.height * ratio
        )

        let newImage = NSImage(size: newSize)
        newImage.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: NSRect(origin: .zero, size: newSize),
            from: NSRect(origin: .zero, size: imageSize),
            operation: .copy,
            fraction: 1.0
        )
        newImage.unlockFocus()

        return newImage
    }
}
