import SwiftData
import SwiftUI

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Book.title) private var books: [Book]
    @State private var searchText = ""
    @State private var sortOrder: SortOrder = .title
    @State private var selectedBook: Book?

    private var filteredBooks: [Book] {
        var result = books

        if !searchText.isEmpty {
            result = result.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
        }

        switch sortOrder {
        case .title:
            result.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .dateAdded:
            result.sort { $0.addedAt > $1.addedAt }
        case .lastOpened:
            result.sort { ($0.lastOpenedAt ?? .distantPast) > ($1.lastOpenedAt ?? .distantPast) }
        }

        return result
    }

    private let gridColumns = [
        GridItem(.adaptive(minimum: Constants.Grid.minItemWidth), spacing: Constants.Grid.spacing)
    ]

    var body: some View {
        VStack(spacing: 0) {
            if filteredBooks.isEmpty {
                emptyStateView
            } else {
                ScrollView {
                    LazyVGrid(columns: gridColumns, spacing: Constants.Grid.spacing) {
                        ForEach(filteredBooks) { book in
                            BookGridItem(
                                book: book,
                                onOpen: {
                                    // Reset selection first to ensure navigation triggers
                                    selectedBook = nil
                                    // Use async to allow SwiftUI to process the nil state
                                    Task { @MainActor in
                                        selectedBook = book
                                    }
                                },
                                onDelete: {
                                    deleteBook(book)
                                }
                            )
                        }
                    }
                    .padding()
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search books")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    importBooks()
                } label: {
                    Label("Add Books", systemImage: "plus")
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker("Sort by", selection: $sortOrder) {
                        ForEach(SortOrder.allCases) { order in
                            Text(order.label).tag(order)
                        }
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
            }
        }
        .navigationDestination(item: $selectedBook) { book in
            ReaderView(book: book)
                .id(book.id)
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "books.vertical")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text("No Books in Library")
                .font(.title2)

            Text("Add manga files or folders to get started")
                .foregroundStyle(.secondary)

            Button("Add Books") {
                importBooks()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func deleteBook(_ book: Book) {
        let filePath = book.filePath
        Task { @MainActor in
            await SecurityScopedBookmarkManager.shared.removeBookmark(for: filePath)
            modelContext.delete(book)
            try? modelContext.save()
        }
    }

    private func importBooks() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.zip, .data, .folder]

        panel.begin { response in
            guard response == .OK else { return }

            Task { @MainActor in
                let viewModel = LibraryViewModel(modelContext: modelContext, startWatching: false)
                for url in panel.urls {
                    await viewModel.addFolder(url)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        LibraryView()
    }
    .modelContainer(for: Book.self, inMemory: true)
}
