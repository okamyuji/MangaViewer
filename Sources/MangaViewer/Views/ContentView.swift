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
    @State private var directOpenURL: URL?
    @State private var isLoading = false
    @State private var loadingError: String?
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic

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
                            if let url = directOpenURL {
                                Task {
                                    await SecurityScopedBookmarkManager.shared.removeBookmark(
                                        for: url.path
                                    )
                                }
                                directOpenURL = nil
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
        isLoading = true
        loadingError = nil

        Task {
            await SecurityScopedBookmarkManager.shared.saveBookmark(for: url)

            do {
                let provider = try ArchiveService.provider(for: url)
                // Load first page as thumbnail
                var thumbnail: NSImage?
                if provider.pageCount > 0 {
                    thumbnail = try? await provider.image(at: 0)
                }
                directOpenProvider = provider
                directOpenTitle = url.deletingPathExtension().lastPathComponent
                directOpenThumbnail = thumbnail
                directOpenURL = url
                isLoading = false
            } catch {
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
