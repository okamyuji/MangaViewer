import SwiftUI

/// Custom slider without the black border
struct CleanSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Track background
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.secondary.opacity(0.25))
                    .frame(height: 4)

                // Track fill (progress)
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor)
                    .frame(width: geometry.size.width * percentage, height: 4)

                // Thumb
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 14, height: 14)
                    .offset(x: geometry.size.width * percentage - 7)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { dragValue in
                                let newPercentage = min(max(0, dragValue.location.x / geometry.size.width), 1)
                                let rawValue = range.lowerBound + (range.upperBound - range.lowerBound) * newPercentage
                                let steppedValue = round(rawValue / step) * step
                                value = min(max(steppedValue, range.lowerBound), range.upperBound)
                            }
                    )
            }
            .frame(height: 14)
        }
        .frame(height: 14)
    }

    private var percentage: Double {
        (value - range.lowerBound) / (range.upperBound - range.lowerBound)
    }
}

struct ReaderToolbar: View {
    @Bindable var viewModel: ReaderViewModel

    var body: some View {
        HStack(spacing: 16) {
            pageNavigation

            Divider()
                .frame(height: 20)

            displayModeControls

            Divider()
                .frame(height: 20)

            zoomControls

            Divider()
                .frame(height: 20)

            bookmarkButton

            Spacer()

            filterButton
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    private var pageNavigation: some View {
        HStack(spacing: 8) {
            if viewModel.readingDirection == .rightToLeft {
                // RTL: Forward button on left (goes to next page)
                Button {
                    viewModel.nextPage()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(viewModel.currentPage >= viewModel.totalPages - 1)

                // RTL slider: max on left, min on right
                CleanSlider(
                    value: Binding(
                        get: { Double(viewModel.totalPages - 1 - viewModel.currentPage) },
                        set: { viewModel.goToPage(viewModel.totalPages - 1 - Int($0)) }
                    ),
                    range: 0 ... Double(max(viewModel.totalPages - 1, 1)),
                    step: 1
                )
                .frame(width: 150)

                Text("\(viewModel.currentPage + 1) / \(viewModel.totalPages)")
                    .monospacedDigit()
                    .frame(minWidth: 80)

                // RTL: Back button on right (goes to previous page)
                Button {
                    viewModel.previousPage()
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(viewModel.currentPage <= 0)
            } else {
                // LTR: standard layout
                Button {
                    viewModel.previousPage()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(viewModel.currentPage <= 0)

                Text("\(viewModel.currentPage + 1) / \(viewModel.totalPages)")
                    .monospacedDigit()
                    .frame(minWidth: 80)

                CleanSlider(
                    value: Binding(
                        get: { Double(viewModel.currentPage) },
                        set: { viewModel.goToPage(Int($0)) }
                    ),
                    range: 0 ... Double(max(viewModel.totalPages - 1, 1)),
                    step: 1
                )
                .frame(width: 150)

                Button {
                    viewModel.nextPage()
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(viewModel.currentPage >= viewModel.totalPages - 1)
            }
        }
    }

    private var displayModeControls: some View {
        HStack(spacing: 4) {
            ForEach(DisplayMode.allCases) { mode in
                Button {
                    viewModel.displayMode = mode
                } label: {
                    Image(systemName: mode.icon)
                }
                .buttonStyle(.plain)
                .foregroundStyle(viewModel.displayMode == mode ? .primary : .secondary)
            }

            Divider()
                .frame(height: 16)

            Menu {
                ForEach(ReadingDirection.allCases) { direction in
                    Button {
                        viewModel.readingDirection = direction
                    } label: {
                        Label(direction.label, systemImage: direction.icon)
                    }
                }
            } label: {
                Image(systemName: viewModel.readingDirection.icon)
            }
        }
    }

    private var zoomControls: some View {
        HStack(spacing: 4) {
            Button {
                viewModel.zoomOut()
            } label: {
                Image(systemName: "minus.magnifyingglass")
            }

            Menu {
                ForEach(ZoomMode.allCases) { mode in
                    Button {
                        viewModel.zoomMode = mode
                        if mode != .custom {
                            viewModel.zoomScale = 1.0
                        }
                    } label: {
                        Label(mode.label, systemImage: mode.icon)
                    }
                }
            } label: {
                Text("\(Int(viewModel.zoomScale * 100))%")
                    .monospacedDigit()
                    .frame(minWidth: 50)
            }

            Button {
                viewModel.zoomIn()
            } label: {
                Image(systemName: "plus.magnifyingglass")
            }
        }
    }

    private var bookmarkButton: some View {
        Button {
            viewModel.addBookmark()
        } label: {
            Image(systemName: "bookmark")
        }
        .help("Add Bookmark (B)")
    }

    private var filterButton: some View {
        Menu {
            VStack {
                Text("Brightness: \(Int(viewModel.filterSettings.brightness * 100))")
                Slider(value: $viewModel.filterSettings.brightness, in: -1 ... 1)

                Text("Contrast: \(Int(viewModel.filterSettings.contrast * 100))")
                Slider(value: $viewModel.filterSettings.contrast, in: 0.5 ... 2)

                Text("Sepia: \(Int(viewModel.filterSettings.sepia * 100))")
                Slider(value: $viewModel.filterSettings.sepia, in: 0 ... 1)

                Toggle("Grayscale", isOn: $viewModel.filterSettings.grayscale)

                Button("Reset Filters") {
                    viewModel.filterSettings = .default
                }
            }
            .padding()
        } label: {
            Image(systemName: "slider.horizontal.3")
        }
        .help("Image Filters")
    }
}

#Preview {
    ReaderToolbar(viewModel: ReaderViewModel())
}
