import SwiftData
import SwiftUI

struct ReaderView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = ReaderViewModel()
    #if os(iOS)
        @FocusState private var isFocused: Bool
    #endif

    let book: Book?
    let provider: PageProvider?
    let bookTitle: String?
    let onClose: (() -> Void)?

    init(book: Book) {
        self.book = book
        provider = nil
        bookTitle = nil
        onClose = nil
    }

    init(provider: PageProvider, bookTitle: String, onClose: @escaping () -> Void) {
        book = nil
        self.provider = provider
        self.bookTitle = bookTitle
        self.onClose = onClose
    }

    var body: some View {
        ZStack {
            Color.readerBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                contentView
                    .background(Color.readerBackground)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("readerContent")
                #if os(iOS)
                    .modifier(TouchReaderControls(viewModel: viewModel, perform: perform))
                #endif
                if showsToolbar {
                    ReaderToolbar(viewModel: viewModel)
                }
            }

            #if os(macOS)
                KeyboardHandlerView { keyCode in
                    guard let command = ReaderCommand(macKeyCode: keyCode) else { return false }
                    perform(command)
                    return true
                }
                .frame(width: 0, height: 0)
            #endif

            if viewModel.showBookmarkToast {
                VStack {
                    Spacer()
                    HStack {
                        Image(systemName: "bookmark.fill")
                        Text(viewModel.bookmarkToastMessage)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 60)
                }
                .animation(.easeInOut(duration: 0.3), value: viewModel.showBookmarkToast)
            }
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
        #if os(iOS)
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onAppear { isFocused = true }
        .onKeyPress { press in
            guard let command = ReaderCommand(key: press.key) else { return .ignored }
            perform(command)
            return .handled
        }
        #endif
    }

    private var showsToolbar: Bool {
        #if os(iOS)
            !viewModel.isFullScreen
        #else
            true
        #endif
    }

    private var hasVisibleImage: Bool {
        viewModel.spreadImages.left != nil || viewModel.spreadImages.right != nil
    }

    @ViewBuilder
    private var contentView: some View {
        if viewModel.isLoading && !hasVisibleImage {
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
            SpreadView(
                leftImage: viewModel.spreadImages.left,
                rightImage: viewModel.spreadImages.right,
                readingDirection: viewModel.readingDirection,
                zoomMode: viewModel.zoomMode,
                zoomScale: $viewModel.zoomScale
            )
        }
    }

    private func perform(_ command: ReaderCommand) {
        guard command == .close else {
            viewModel.perform(command)
            return
        }
        if let onClose {
            onClose()
        } else {
            dismiss()
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
