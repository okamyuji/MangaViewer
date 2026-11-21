#if os(iOS)
    import SwiftUI

    /// Tap zones, swipes and orientation-dependent single-page display for the iPad reader.
    struct TouchReaderControls: ViewModifier {
        let viewModel: ReaderViewModel
        let perform: (ReaderCommand) -> Void
        @State private var pageOverflowsHorizontally = false

        func body(content: Content) -> some View {
            GeometryReader { geometry in
                content
                    .contentShape(Rectangle())
                    .gesture(
                        SpatialTapGesture()
                            .onEnded { tap in
                                handle(ReaderGesture.tapAction(
                                    locationX: tap.location.x, width: geometry.size.width,
                                    direction: viewModel.readingDirection
                                ))
                            }
                    )
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 20)
                            .onEnded { drag in
                                if let action = ReaderGesture.swipeAction(
                                    translation: drag.translation, zoomScale: viewModel.zoomScale, overflowsHorizontally: pageOverflowsHorizontally,
                                    direction: viewModel.readingDirection
                                ) {
                                    handle(action)
                                }
                            }
                    )
                    .onPreferenceChange(PageOverflowsHorizontallyKey.self) { overflows in
                        pageOverflowsHorizontally = overflows
                    }
                    .onAppear {
                        viewModel.setPrefersSinglePage(ReaderGesture.prefersSinglePage(containerSize: geometry.size))
                    }
                    .onChange(of: geometry.size) { _, size in
                        viewModel.setPrefersSinglePage(ReaderGesture.prefersSinglePage(containerSize: size))
                    }
            }
        }

        private func handle(_ action: ReaderAction) {
            switch action {
            case .next: perform(.next)
            case .previous: perform(.previous)
            case .toggleChrome: perform(.toggleFullScreen)
            }
        }
    }
#endif
