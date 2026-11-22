import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    #if DEBUG
        @Environment(LibraryViewModel.self) private var library: LibraryViewModel?
    #endif
    @Query private var books: [Book]

    @State private var directOpenProvider: PageProvider?
    @State private var directOpenTitle: String?
    @State private var directOpenAccessingURL: URL?
    @State private var isLoading = false
    @State private var loadingError: String?
    #if os(iOS)
        /// .automatic hides the sidebar on a portrait iPad, and with it the book list, Add Books and Settings
        @State private var columnVisibility: NavigationSplitViewVisibility = .all
    #else
        @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    #endif
    @State private var openFileTask: Task<Void, Never>?
    @State private var openRequestID: Int = 0

    var body: some View {
        Group {
            if let provider = directOpenProvider, let title = directOpenTitle {
                // Direct file open - full screen reader without sidebars
                NavigationStack {
                    ReaderView(
                        provider: provider,
                        bookTitle: title,
                        onClose: {
                            directOpenProvider?.close()
                            directOpenProvider = nil
                            directOpenTitle = nil
                            if let url = directOpenAccessingURL {
                                url.stopAccessingSecurityScopedResource()
                                directOpenAccessingURL = nil
                            }
                        }
                    )
                }
                #if os(macOS)
                .frame(minWidth: 800, minHeight: 600)
                #endif
            } else {
                NavigationSplitView(columnVisibility: $columnVisibility) {
                    SidebarView(columnVisibility: $columnVisibility)
                    #if os(iOS)
                        // Narrower than this, the sidebar bar folds Settings and Add Books into an overflow menu
                        .navigationSplitViewColumnWidth(min: 300, ideal: 320, max: 400)
                    #else
                        .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
                    #endif
                } detail: {
                    Text("Select a book to read")
                        .foregroundStyle(.secondary)
                }
                #if os(macOS)
                .frame(minWidth: 800, minHeight: 600)
                #endif
            }
        }
        .overlay {
            if isLoading {
                ZStack {
                    Color.black.opacity(0.3)
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Opening file...")
                            .foregroundStyle(.white)
                    }
                    .padding(40)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
        .alert(
            "Error",
            isPresented: .init(
                get: { loadingError != nil || appState.showError },
                set: {
                    if !$0 {
                        loadingError = nil
                        appState.showError = false
                    }
                }
            )
        ) {
            Button("OK") {
                loadingError = nil
                appState.showError = false
                appState.openError = nil
            }
        } message: {
            Text(loadingError ?? appState.openError ?? "Unknown error")
        }
        #if DEBUG
        .task {
            openSampleBookIfRequested()
        }
        #endif
        .onChange(of: appState.fileToOpen) { _, newURL in
            if let url = newURL {
                openFileDirectly(url)
                appState.clearFileToOpen()
            }
        }
    }

    #if DEBUG
        private func openSampleBookIfRequested() {
            if ProcessInfo.processInfo.arguments.contains(SampleBook.seriesLaunchArgument) {
                let folder = FileManager.default.temporaryDirectory.appendingPathComponent("UITestSeries")
                do {
                    try SampleBook.writeSeries(in: folder)
                    Task { await library?.addFolder(folder) }
                } catch {
                    loadingError = error.localizedDescription
                }
                return
            }
            if ProcessInfo.processInfo.arguments.contains(SampleBook.libraryLaunchArgument) {
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("UITestLibrary.cbz")
                do {
                    try SampleBook.writeCBZ(to: url, pageCount: 6, widePages: [2])
                    Task { await library?.addFolder(url) }
                } catch {
                    loadingError = error.localizedDescription
                }
                return
            }
            guard ProcessInfo.processInfo.arguments.contains(SampleBook.launchArgument) else { return }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("UITestSample.cbz")
            do {
                try SampleBook.writeCBZ(to: url, pageCount: 4)
                appState.openFile(url)
            } catch {
                loadingError = error.localizedDescription
            }
        }
    #endif

    private func openFileDirectly(_ url: URL) {
        // Cancel any in-flight open task
        openFileTask?.cancel()

        // Close existing provider/access before opening a new file
        directOpenProvider?.close()
        directOpenProvider = nil
        if let previousURL = directOpenAccessingURL {
            previousURL.stopAccessingSecurityScopedResource()
            directOpenAccessingURL = nil
        }

        isLoading = true
        loadingError = nil

        let accessing = url.startAccessingSecurityScopedResource()
        let title = url.deletingPathExtension().lastPathComponent
        openRequestID += 1
        let requestID = openRequestID

        // Outer Task inherits MainActor; inner detached task avoids capturing self
        openFileTask = Task {
            let result: Result<PageProvider, Error> = await Task.detached {
                Result { try ArchiveService.provider(for: url) }
            }.value

            // Back on MainActor - check cancellation and stale request
            guard !Task.isCancelled, openRequestID == requestID else {
                if case let .success(provider) = result {
                    provider.close()
                }
                if accessing {
                    url.stopAccessingSecurityScopedResource()
                }
                return
            }

            switch result {
            case let .success(provider):
                directOpenProvider = provider
                directOpenTitle = title
                if accessing {
                    directOpenAccessingURL = url
                }
                isLoading = false
            case let .failure(error):
                if accessing {
                    url.stopAccessingSecurityScopedResource()
                }
                isLoading = false
                loadingError = error.localizedDescription
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Book.self, inMemory: true)
        .environment(AppState.shared)
}
