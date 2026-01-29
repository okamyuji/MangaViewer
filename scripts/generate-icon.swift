#!/usr/bin/env swift

import AppKit
import Foundation

// Icon sizes required for macOS app icons
let sizes: [(size: Int, scale: Int, suffix: String)] = [
    (16, 1, "16x16"),
    (16, 2, "16x16@2x"),
    (32, 1, "32x32"),
    (32, 2, "32x32@2x"),
    (128, 1, "128x128"),
    (128, 2, "128x128@2x"),
    (256, 1, "256x256"),
    (256, 2, "256x256@2x"),
    (512, 1, "512x512"),
    (512, 2, "512x512@2x")
]

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))

    image.lockFocus()

    let context = NSGraphicsContext.current!.cgContext

    // Background - rounded rectangle with gradient
    let cornerRadius = size * 0.18
    let bounds = CGRect(x: 0, y: 0, width: size, height: size)
    let path = CGPath(roundedRect: bounds.insetBy(dx: size * 0.02, dy: size * 0.02),
                      cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

    // Gradient background - deep purple to dark blue
    context.saveGState()
    context.addPath(path)
    context.clip()

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let colors = [
        CGColor(red: 0.15, green: 0.08, blue: 0.25, alpha: 1.0), // Deep purple
        CGColor(red: 0.08, green: 0.12, blue: 0.28, alpha: 1.0) // Dark blue
    ] as CFArray

    if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0, 1]) {
        context.drawLinearGradient(gradient,
                                   start: CGPoint(x: 0, y: size),
                                   end: CGPoint(x: size, y: 0),
                                   options: [])
    }
    context.restoreGState()

    // Draw stylized book/manga pages
    let pageWidth = size * 0.32
    let pageHeight = size * 0.55
    let centerX = size / 2
    let centerY = size / 2 + size * 0.02

    // Left page (slightly rotated)
    context.saveGState()
    context.translateBy(x: centerX - size * 0.02, y: centerY)
    context.rotate(by: 0.12)

    let leftPage = CGRect(x: -pageWidth, y: -pageHeight / 2, width: pageWidth, height: pageHeight)
    let leftPagePath = CGPath(roundedRect: leftPage, cornerWidth: size * 0.02, cornerHeight: size * 0.02, transform: nil)

    // Page shadow
    context.setShadow(offset: CGSize(width: -2, height: -2), blur: size * 0.05, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.4))
    context.setFillColor(CGColor(red: 0.95, green: 0.93, blue: 0.88, alpha: 1.0))
    context.addPath(leftPagePath)
    context.fillPath()

    // Page lines (manga panel effect)
    context.setShadow(offset: .zero, blur: 0)
    context.setStrokeColor(CGColor(red: 0.7, green: 0.68, blue: 0.65, alpha: 0.6))
    context.setLineWidth(size * 0.008)

    for i in 1 ... 4 {
        let y = leftPage.minY + leftPage.height * CGFloat(i) / 5
        context.move(to: CGPoint(x: leftPage.minX + size * 0.03, y: y))
        context.addLine(to: CGPoint(x: leftPage.maxX - size * 0.03, y: y))
    }
    context.strokePath()

    context.restoreGState()

    // Right page (slightly rotated opposite)
    context.saveGState()
    context.translateBy(x: centerX + size * 0.02, y: centerY)
    context.rotate(by: -0.12)

    let rightPage = CGRect(x: 0, y: -pageHeight / 2, width: pageWidth, height: pageHeight)
    let rightPagePath = CGPath(roundedRect: rightPage, cornerWidth: size * 0.02, cornerHeight: size * 0.02, transform: nil)

    context.setShadow(offset: CGSize(width: 2, height: -2), blur: size * 0.05, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.4))
    context.setFillColor(CGColor(red: 0.98, green: 0.96, blue: 0.92, alpha: 1.0))
    context.addPath(rightPagePath)
    context.fillPath()

    // Manga-style action lines on right page
    context.setShadow(offset: .zero, blur: 0)
    context.setStrokeColor(CGColor(red: 0.3, green: 0.3, blue: 0.35, alpha: 0.3))
    context.setLineWidth(size * 0.006)

    let lineCenter = CGPoint(x: rightPage.midX, y: rightPage.midY)
    for angle in stride(from: 0.0, to: Double.pi * 2, by: Double.pi / 8) {
        let startRadius = size * 0.08
        let endRadius = size * 0.18
        let cosAngle = CGFloat(Darwin.cos(angle))
        let sinAngle = CGFloat(Darwin.sin(angle))
        context.move(to: CGPoint(x: lineCenter.x + cosAngle * startRadius,
                                 y: lineCenter.y + sinAngle * startRadius))
        context.addLine(to: CGPoint(x: lineCenter.x + cosAngle * endRadius,
                                    y: lineCenter.y + sinAngle * endRadius))
    }
    context.strokePath()

    context.restoreGState()

    // Center binding
    context.saveGState()
    let bindingRect = CGRect(x: centerX - size * 0.02, y: centerY - pageHeight / 2 - size * 0.02,
                             width: size * 0.04, height: pageHeight + size * 0.04)
    context.setShadow(offset: .zero, blur: size * 0.02, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.5))
    context.setFillColor(CGColor(red: 0.2, green: 0.18, blue: 0.22, alpha: 1.0))
    context.fill(bindingRect)
    context.restoreGState()

    // Accent - Japanese character "漫" stylized element (simplified)
    context.saveGState()
    let accentSize = size * 0.15
    let accentX = size * 0.78
    let accentY = size * 0.22

    // Circular badge
    context.setShadow(offset: CGSize(width: 1, height: -1), blur: size * 0.02, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.3))
    context.setFillColor(CGColor(red: 0.95, green: 0.3, blue: 0.35, alpha: 1.0)) // Vibrant red
    context.fillEllipse(in: CGRect(x: accentX - accentSize / 2, y: accentY - accentSize / 2, width: accentSize, height: accentSize))

    // "M" for Manga in the badge
    context.setShadow(offset: .zero, blur: 0)
    context.setFillColor(.white)
    context.setLineWidth(size * 0.015)
    context.setStrokeColor(.white)

    let mX = accentX - accentSize * 0.25
    let mY = accentY - accentSize * 0.2
    let mWidth = accentSize * 0.5
    let mHeight = accentSize * 0.4

    context.move(to: CGPoint(x: mX, y: mY))
    context.addLine(to: CGPoint(x: mX, y: mY + mHeight))
    context.move(to: CGPoint(x: mX, y: mY + mHeight))
    context.addLine(to: CGPoint(x: mX + mWidth / 2, y: mY + mHeight * 0.4))
    context.addLine(to: CGPoint(x: mX + mWidth, y: mY + mHeight))
    context.move(to: CGPoint(x: mX + mWidth, y: mY))
    context.addLine(to: CGPoint(x: mX + mWidth, y: mY + mHeight))
    context.strokePath()

    context.restoreGState()

    image.unlockFocus()

    return image
}

// Generate icons
let iconsetPath = "Resources/AppIcon.iconset"
let fileManager = FileManager.default

// Create directory if needed
try? fileManager.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

for (size, scale, suffix) in sizes {
    let pixelSize = size * scale
    let icon = drawIcon(size: CGFloat(pixelSize))

    guard let tiffData = icon.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:])
    else {
        print("Failed to create PNG for \(suffix)")
        continue
    }

    let filename = "\(iconsetPath)/icon_\(suffix).png"
    do {
        try pngData.write(to: URL(fileURLWithPath: filename))
        print("Created: \(filename)")
    } catch {
        print("Failed to write \(filename): \(error)")
    }
}

print("\nGenerating .icns file...")
let iconsetURL = URL(fileURLWithPath: iconsetPath)
let icnsPath = "Resources/AppIcon.icns"

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetPath, "-o", icnsPath]

do {
    try process.run()
    process.waitUntilExit()
    if process.terminationStatus == 0 {
        print("✅ Created: \(icnsPath)")
    } else {
        print("❌ iconutil failed with status \(process.terminationStatus)")
    }
} catch {
    print("❌ Failed to run iconutil: \(error)")
}
