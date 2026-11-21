import SwiftUI

struct ZoomableImageView: View {
    let image: PlatformImage
    let zoomMode: ZoomMode
    @Binding var zoomScale: CGFloat

    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var pinchBaseScale: CGFloat?
    /// Resets on its own when the system cancels a pinch, which skips onEnded.
    @GestureState private var isPinching = false

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
                        .updating($isPinching) { _, pinching, _ in pinching = true }
                        .onChanged { value in
                            let base = pinchBaseScale ?? zoomScale
                            pinchBaseScale = base
                            zoomScale = ReaderGesture.pinchScale(base: base, magnification: value.magnification)
                        }
                        .onEnded { _ in
                            pinchBaseScale = nil
                        }
                )
                .simultaneousGesture(
                    DragGesture()
                        .onChanged { value in
                            #if os(iOS)
                                let translation = ReaderGesture.panTranslation(
                                    value.translation, contentSize: displayedSize(imageSize),
                                    containerSize: geometry.size
                                )
                            #else
                                let translation = value.translation
                            #endif
                            offset = CGSize(
                                width: lastOffset.width + translation.width,
                                height: lastOffset.height + translation.height
                            )
                            #if os(iOS)
                                offset = ReaderGesture.clampedOffset(
                                    offset, contentSize: displayedSize(imageSize), containerSize: geometry.size
                                )
                            #endif
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
                .onChange(of: isPinching) { _, pinching in
                    if !pinching {
                        pinchBaseScale = nil
                    }
                }
            #if os(iOS)
                .onChange(of: zoomScale) {
                    recenter(imageSize: calculateImageSize(for: geometry.size), containerSize: geometry.size)
                }
                .onChange(of: zoomMode) {
                    recenter(imageSize: calculateImageSize(for: geometry.size), containerSize: geometry.size)
                }
                .onChange(of: geometry.size) {
                    recenter(imageSize: calculateImageSize(for: geometry.size), containerSize: geometry.size)
                }
                .preference(
                    key: PageOverflowsHorizontallyKey.self,
                    value: ReaderGesture.overflows(displayedSize(imageSize).width, geometry.size.width)
                )
            #endif
        }
    }

    private func displayedSize(_ imageSize: CGSize) -> CGSize {
        CGSize(width: imageSize.width * zoomScale, height: imageSize.height * zoomScale)
    }

    private func recenter(imageSize: CGSize, containerSize: CGSize) {
        offset = ReaderGesture.clampedOffset(offset, contentSize: displayedSize(imageSize), containerSize: containerSize)
        lastOffset = offset
    }

    private func calculateImageSize(for containerSize: CGSize) -> CGSize {
        let imageWidth = image.size.width
        let imageHeight = image.size.height
        // The error placeholder can be an empty image; dividing by its zero size gives NaN frames
        guard imageWidth > 0, imageHeight > 0 else { return .zero }

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

#if os(iOS)
    /// True when any page on screen is wider than its half of the reader, so a horizontal drag
    /// pans it instead of turning the page.
    struct PageOverflowsHorizontallyKey: PreferenceKey {
        static let defaultValue = false

        static func reduce(value: inout Bool, nextValue: () -> Bool) {
            value = value || nextValue()
        }
    }
#endif
