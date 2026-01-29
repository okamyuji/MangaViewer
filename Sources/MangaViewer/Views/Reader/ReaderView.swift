import SwiftData
import SwiftUI

struct ReaderView: View {
  @Environment(\.modelContext) private var modelContext
  @Environment(\.dismiss) private var dismiss
  @State private var viewModel = ReaderViewModel()

  let book: Book?
  let provider: PageProvider?
  let bookTitle: String?
  let onClose: (() -> Void)?

  init(book: Book) {
    self.book = book
    self.provider = nil
    self.bookTitle = nil
    self.onClose = nil
  }

  init(provider: PageProvider, bookTitle: String, onClose: @escaping () -> Void) {
    self.book = nil
    self.provider = provider
    self.bookTitle = bookTitle
    self.onClose = onClose
  }

  var body: some View {
    ZStack {
      Color(nsColor: .windowBackgroundColor)
        .ignoresSafeArea()

      VStack(spacing: 0) {
        contentView
          .background(Color(nsColor: .windowBackgroundColor))
        ReaderToolbar(viewModel: viewModel)
      }

      KeyboardHandlerView { keyCode in
        handleKeyCode(keyCode)
      }
      .frame(width: 0, height: 0)
    }
    .navigationTitle(book?.title ?? bookTitle ?? "Reader")
    .navigationBarBackButtonHidden(viewModel.isFullScreen)
    .toolbar(viewModel.isFullScreen ? .hidden : .automatic)
    .toolbar {
      if onClose != nil {
        ToolbarItem(placement: .cancellationAction) {
          Button("Close") {
            onClose?()
          }
        }
      }
    }
    .onAppear {
      Task {
        if let book {
          await viewModel.openBook(book, modelContext: modelContext)
        } else if let provider, let title = bookTitle {
          await viewModel.openProvider(provider, title: title)
        }
      }
    }
    .onDisappear {
      viewModel.closeBook()
    }
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
          if let onClose {
            onClose()
          } else {
            dismiss()
          }
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

  // macOS key codes
  private static let keyCodeLeftArrow: UInt16 = 123
  private static let keyCodeRightArrow: UInt16 = 124
  private static let keyCodeSpace: UInt16 = 49
  private static let keyCodeEscape: UInt16 = 53
  private static let keyCodeF: UInt16 = 3
  private static let keyCode1: UInt16 = 18
  private static let keyCode2: UInt16 = 19
  private static let keyCodeB: UInt16 = 11
  private static let keyCode0: UInt16 = 29
  private static let keyCodeEqual: UInt16 = 24
  private static let keyCodeMinus: UInt16 = 27

  private func handleKeyCode(_ keyCode: UInt16) -> Bool {
    switch keyCode {
    case Self.keyCodeLeftArrow:
      if viewModel.readingDirection == .rightToLeft {
        viewModel.nextPage()
      } else {
        viewModel.previousPage()
      }
      return true

    case Self.keyCodeRightArrow:
      if viewModel.readingDirection == .rightToLeft {
        viewModel.previousPage()
      } else {
        viewModel.nextPage()
      }
      return true

    case Self.keyCodeSpace:
      viewModel.nextPage()
      return true

    case Self.keyCodeF:
      viewModel.toggleFullScreen()
      return true

    case Self.keyCode1:
      viewModel.displayMode = .single
      return true

    case Self.keyCode2:
      viewModel.displayMode = .spread
      return true

    case Self.keyCodeB:
      viewModel.addBookmark()
      return true

    case Self.keyCode0:
      viewModel.resetZoom()
      return true

    case Self.keyCodeEqual:
      viewModel.zoomIn()
      return true

    case Self.keyCodeMinus:
      viewModel.zoomOut()
      return true

    case Self.keyCodeEscape:
      if let onClose {
        onClose()
      } else {
        dismiss()
      }
      return true

    default:
      return false
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
