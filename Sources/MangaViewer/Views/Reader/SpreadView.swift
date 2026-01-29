import SwiftUI

struct SpreadView: View {
    let leftImage: NSImage?
    let rightImage: NSImage?
    let readingDirection: ReadingDirection
    let zoomMode: ZoomMode
    @Binding var zoomScale: CGFloat

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                pageView(for: leftImage, width: geometry.size.width / 2)
                pageView(for: rightImage, width: geometry.size.width / 2)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }

    @ViewBuilder
    private func pageView(for image: NSImage?, width: CGFloat) -> some View {
        if let image {
            ZoomableImageView(
                image: image,
                zoomMode: zoomMode,
                zoomScale: $zoomScale
            )
            .frame(width: width)
        } else {
            Color.clear
                .frame(width: width)
        }
    }
}

#Preview {
    SpreadView(
        leftImage: NSImage(systemSymbolName: "photo", accessibilityDescription: nil),
        rightImage: NSImage(systemSymbolName: "photo", accessibilityDescription: nil),
        readingDirection: .rightToLeft,
        zoomMode: .fitPage,
        zoomScale: .constant(1.0)
    )
}
