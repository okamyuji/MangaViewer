import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

struct ImageFilterSettings: Equatable {
    var brightness: Float = 0
    var contrast: Float = 1
    var sepia: Float = 0
    var grayscale: Bool = false

    static let `default` = ImageFilterSettings()

    var isDefault: Bool {
        self == .default
    }
}

enum ImageFilterApplier {
    private static let context = CIContext()

    static func apply(_ settings: ImageFilterSettings, to image: NSImage) -> NSImage {
        guard !settings.isDefault else { return image }

        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return image
        }

        var ciImage = CIImage(cgImage: cgImage)

        if settings.brightness != 0 || settings.contrast != 1 {
            let colorControls = CIFilter.colorControls()
            colorControls.inputImage = ciImage
            colorControls.brightness = settings.brightness
            colorControls.contrast = settings.contrast
            if let output = colorControls.outputImage {
                ciImage = output
            }
        }

        if settings.sepia > 0 {
            let sepiaFilter = CIFilter.sepiaTone()
            sepiaFilter.inputImage = ciImage
            sepiaFilter.intensity = settings.sepia
            if let output = sepiaFilter.outputImage {
                ciImage = output
            }
        }

        if settings.grayscale {
            let monoFilter = CIFilter.photoEffectMono()
            monoFilter.inputImage = ciImage
            if let output = monoFilter.outputImage {
                ciImage = output
            }
        }

        guard let outputCGImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return image
        }

        return NSImage(cgImage: outputCGImage, size: image.size)
    }
}
