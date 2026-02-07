import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @Query private var books: [Book]

    @State private var selectedBook: Book?
    @State private var directOpenProvider: PageProvider?
    @State private var directOpenTitle: String?
    @State private var directOpenThumbnail: NSImage?
    @State private var directOpenAccessingURL: URL?
    @State private var isLoading = false
    @State private var loadingError: String?
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
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
                            directOpenThumbnail = nil
                            if let url = directOpenAccessingURL {
                                url.stopAccessingSecurityScopedResource()
                                directOpenAccessingURL = nil
                            }
                        }
                    )
                }
                .frame(minWidth: 800, minHeight: 600)
            } else {
                NavigationSplitView(columnVisibility: $columnVisibility) {
                    SidebarView()
                        .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
                } detail: {
                    Text("Select a book to read")
                        .foregroundStyle(.secondary)
                }
                .frame(minWidth: 800, minHeight: 600)
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
        .onChange(of: appState.fileToOpen) { _, newURL in
            if let url = newURL {
                openFileDirectly(url)
                appState.clearFileToOpen()
            }
        }
    }

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

        openFileTask = Task.detached {
            do {
                let provider = try ArchiveService.provider(for: url)
                let thumbnail: NSImage? = if provider.pageCount > 0 {
                    try? await provider.image(at: 0)
                } else {
                    nil
                }
                guard !Task.isCancelled else {
                    provider.close()
                    if accessing { url.stopAccessingSecurityScopedResource() }
                    return
                }
                await MainActor.run {
                    guard self.openRequestID == requestID else {
                        provider.close()
                        if accessing { url.stopAccessingSecurityScopedResource() }
                        return
                    }
                    self.directOpenProvider = provider
                    self.directOpenTitle = title
                    self.directOpenThumbnail = thumbnail
                    if accessing {
                        self.directOpenAccessingURL = url
                    }
                    self.isLoading = false
                }
            } catch {
                guard !Task.isCancelled else {
                    if accessing { url.stopAccessingSecurityScopedResource() }
                    return
                }
                await MainActor.run {
                    guard self.openRequestID == requestID else { return }
                    if accessing {
                        url.stopAccessingSecurityScopedResource()
                    }
                    self.isLoading = false
                    self.loadingError = error.localizedDescription
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Book.self, inMemory: true)
        .environment(AppState.shared)
}
