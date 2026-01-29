import SwiftData
import SwiftUI

struct ReaderView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = ReaderViewModel()

    let book: Book

    var body: some View {
        VStack(spacing: 0) {
            contentView
            ReaderToolbar(viewModel: viewModel)
        }
        .navigationTitle(book.title)
        .navigationBarBackButtonHidden(viewModel.isFullScreen)
        .toolbar(viewModel.isFullScreen ? .hidden : .automatic)
        .onAppear {
            Task {
                await viewModel.openBook(book, modelContext: modelContext)
            }
        }
        .onDisappear {
            viewModel.closeBook()
        }
        .onKeyPress { key in
            handleKeyPress(key)
        }
        .focusable()
    }

    @ViewBuilder
    private var contentView: some View {
        if viewModel.isLoading && viewModel.currentImage == nil {
            ProgressView("Loading...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage = viewModel.errorMessage {
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundStyle(.orange)
                Text(errorMessage)
                Button("Go Back") {
                    dismiss()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            pageContent
        }
    }

    @ViewBuilder
    private var pageContent: some View {
        switch viewModel.displayMode {
        case .single:
            PageView(
                image: viewModel.currentImage,
                zoomMode: viewModel.zoomMode,
                zoomScale: $viewModel.zoomScale
            )
        case .spread:
            SpreadView(
                leftImage: viewModel.spreadImages.left,
                rightImage: viewModel.spreadImages.right,
                readingDirection: viewModel.readingDirection,
                zoomMode: viewModel.zoomMode,
                zoomScale: $viewModel.zoomScale
            )
        }
    }

    private func handleKeyPress(_ key: KeyPress) -> KeyPress.Result {
        switch key.key {
        case .leftArrow:
            if viewModel.readingDirection == .rightToLeft {
                viewModel.nextPage()
            } else {
                viewModel.previousPage()
            }
            return .handled

        case .rightArrow:
            if viewModel.readingDirection == .rightToLeft {
                viewModel.previousPage()
            } else {
                viewModel.nextPage()
            }
            return .handled

        case .space:
            if key.modifiers.contains(.shift) {
                viewModel.previousPage()
            } else {
                viewModel.nextPage()
            }
            return .handled

        case .init("f"):
            viewModel.toggleFullScreen()
            return .handled

        case .init("1"):
            viewModel.displayMode = .single
            return .handled

        case .init("2"):
            viewModel.displayMode = .spread
            return .handled

        case .init("b"):
            viewModel.addBookmark()
            return .handled

        case .init("0"):
            viewModel.resetZoom()
            return .handled

        case .init("="), .init("+"):
            viewModel.zoomIn()
            return .handled

        case .init("-"):
            viewModel.zoomOut()
            return .handled

        default:
            return .ignored
        }
    }
}

#Preview {
    NavigationStack {
        ReaderView(
            book: Book(title: "Sample", filePath: "/path", type: .cbz, totalPages: 10)
        )
    }
    .modelContainer(for: Book.self, inMemory: true)
}
