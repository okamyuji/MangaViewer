import SwiftUI

struct PageView: View {
    let image: NSImage?
    let zoomMode: ZoomMode
    @Binding var zoomScale: CGFloat

    var body: some View {
        if let image {
            ZoomableImageView(
                image: image,
                zoomMode: zoomMode,
                zoomScale: $zoomScale
            )
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

#Preview {
    PageView(
        image: NSImage(systemSymbolName: "photo", accessibilityDescription: nil),
        zoomMode: .fitPage,
        zoomScale: .constant(1.0)
    )
}
