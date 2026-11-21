import SwiftUI

struct ZoomableImageView: View {
    let image: PlatformImage
    let zoomMode: ZoomMode
    @Binding var zoomScale: CGFloat

    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            let imageSize = calculateImageSize(for: geometry.size)

            Image(platformImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: imageSize.width * zoomScale, height: imageSize.height * zoomScale)
                .offset(offset)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
                .gesture(
                    MagnifyGesture()
                        .onChanged { value in
                            let newScale = max(0.25, min(5.0, zoomScale * value.magnification))
                            zoomScale = newScale
                        }
                )
                .simultaneousGesture(
                    DragGesture()
                        .onChanged { value in
                            #if os(iOS)
                                // At fit size a horizontal drag is a page-turn swipe, not a pan
                                guard zoomScale > 1 else { return }
                            #endif
                            offset = CGSize(
                                width: lastOffset.width + value.translation.width,
                                height: lastOffset.height + value.translation.height
                            )
                        }
                        .onEnded { _ in
                            lastOffset = offset
                        }
                )
                .onTapGesture(count: 2) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        zoomScale = 1.0
                        offset = .zero
                        lastOffset = .zero
                    }
                }
                .onChange(of: image) {
                    offset = .zero
                    lastOffset = .zero
                }
        }
    }

    private func calculateImageSize(for containerSize: CGSize) -> CGSize {
        let imageWidth = image.size.width
        let imageHeight = image.size.height

        switch zoomMode {
        case .fitPage:
            let widthRatio = containerSize.width / imageWidth
            let heightRatio = containerSize.height / imageHeight
            let ratio = min(widthRatio, heightRatio)
            return CGSize(width: imageWidth * ratio, height: imageHeight * ratio)

        case .fitWidth:
            let ratio = containerSize.width / imageWidth
            return CGSize(width: containerSize.width, height: imageHeight * ratio)

        case .fitHeight:
            let ratio = containerSize.height / imageHeight
            return CGSize(width: imageWidth * ratio, height: containerSize.height)

        case .actualSize:
            return CGSize(width: imageWidth, height: imageHeight)

        case .custom:
            return CGSize(width: imageWidth, height: imageHeight)
        }
    }
}
