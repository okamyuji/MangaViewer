import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct SidebarView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(LibraryViewModel.self) private var library: LibraryViewModel?
    @Query(sort: \Book.title) private var books: [Book]
    @Query(sort: \Tag.name) private var tags: [Tag]

    @Binding var columnVisibility: NavigationSplitViewVisibility

    #if os(iOS)
        /// Sort lives in the overflow menu so Settings and Add Books stay visible in the sidebar bar.
        private static let sortPlacement = ToolbarItemPlacement.secondaryAction
    #else
        private static let sortPlacement = ToolbarItemPlacement.primaryAction
    #endif

    @State private var searchText = ""
    @State private var sortOrder: SortOrder = .title
    @State private var selection = Set<Book>()
    @State private var booksPendingDeletion: [Book] = []
    @State private var showDeleteConfirmation = false
    @State private var navigationBook: Book?
    @State private var readerBook: Book?
    @State private var showAddTagSheet = false
    @State private var selectedTag: Tag?
    @State private var showImporter = false
    @State private var showSettings = false
    #if os(iOS)
        @State private var editMode: EditMode = .inactive
    #endif

    private var filteredBooks: [Book] {
        var result = books

        if !searchText.isEmpty {
            result = result.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
        }

        if let tag = selectedTag {
            result = result.filter { $0.tags.contains { $0.id == tag.id } }
        }

        switch sortOrder {
        case .title:
            result.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .dateAdded:
            result.sort { $0.addedAt > $1.addedAt }
        case .lastOpened:
            result.sort { ($0.lastOpenedAt ?? .distantPast) > ($1.lastOpenedAt ?? .distantPast) }
        }

        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.callout)
                TextField("Search", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            List(selection: $selection) {
                // Library Section with books
                Section("Library") {
                    ForEach(filteredBooks) { book in
                        BookRow(book: book)
                            .tag(book)
                    }
                }

                // Tags Section
                Section("Tags") {
                    Button {
                        selectedTag = nil
                    } label: {
                        Label("All Books", systemImage: "books.vertical")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(selectedTag == nil ? .primary : .secondary)

                    ForEach(tags) { tag in
                        Button {
                            selectedTag = tag
                        } label: {
                            Label(tag.name, systemImage: "tag")
                                .foregroundStyle(Color(hex: tag.colorHex) ?? .accentColor)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(selectedTag?.id == tag.id ? .primary : .secondary)
                        .contextMenu {
                            Button("Delete", role: .destructive) {
                                deleteTag(tag)
                            }
                        }
                    }

                    Button {
                        showAddTagSheet = true
                    } label: {
                        Label("Add Tag", systemImage: "plus")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            .listStyle(.sidebar)
            // Right-clicking a selected row acts on the whole selection, any other row on that row alone
            .contextMenu(forSelectionType: Book.self) { items in
                if !items.isEmpty {
                    Button(items.count == 1 ? "Delete Book" : "Delete \(items.count) Books", role: .destructive) {
                        confirmDeletion(of: items)
                    }
                }
            }
            #if os(iOS)
            .environment(\.editMode, $editMode)
            .refreshable {
                await library?.rescanWatchedFolders()
            }
            #endif
        }
        .toolbar {
            #if os(iOS)
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            #endif

            #if os(iOS)
                ToolbarItem(placement: .topBarLeading) {
                    Button(editMode.isEditing ? "Done" : "Select") {
                        selection.removeAll()
                        editMode = editMode.isEditing ? .inactive : .active
                    }
                }

                if editMode.isEditing {
                    ToolbarItem(placement: .bottomBar) {
                        Button("Delete", role: .destructive) {
                            confirmDeletion(of: selection)
                        }
                        .disabled(selection.isEmpty)
                        .accessibilityIdentifier("deleteSelectedBooks")
                    }
                }
            #endif

            ToolbarItem(placement: .primaryAction) {
                Button {
                    showImporter = true
                } label: {
                    Image(systemName: "plus")
                }
                .help("Add Books")
                .accessibilityLabel("Add Books")
            }

            ToolbarItem(placement: Self.sortPlacement) {
                Menu {
                    Picker("Sort by", selection: $sortOrder) {
                        ForEach(SortOrder.allCases) { order in
                            Text(order.label).tag(order)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .help("Sort")
            }
        }
        .navigationDestination(item: $navigationBook) { book in
            ReaderView(book: book) { readerBook = $0 }
                .id(book.id)
        }
        #if os(iOS)
        // The reader gets the whole screen; the library comes back when it closes
        .onChange(of: navigationBook) { _, book in
            columnVisibility = book == nil ? .all : .detailOnly
        }
        #endif
        .onChange(of: selection) { _, newSelection in
            // Picking more books, or picking in select mode, gathers them for deletion instead of opening one
            guard newSelection.count == 1, let book = newSelection.first else { return }
            #if os(iOS)
                guard !editMode.isEditing else { return }
            #endif
            // Reset navigation first to ensure it triggers even for the same book
            navigationBook = nil
            Task { @MainActor in
                navigationBook = book
            }
        }
        .confirmationDialog(
            booksPendingDeletion.count == 1
                ? "Delete \"\(booksPendingDeletion.first?.title ?? "")\"?"
                : "Delete \(booksPendingDeletion.count) books?",
            isPresented: $showDeleteConfirmation
        ) {
            Button("Delete", role: .destructive) {
                deleteBooks(booksPendingDeletion)
            }
        } message: {
            Text("The files stay on disk; only the library entries are removed.")
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.zip, .data, .folder],
            allowsMultipleSelection: true
        ) { result in
            let urls: [URL]
            switch result {
            case let .success(picked):
                urls = picked
            case let .failure(error):
                AppState.shared.openError = error.localizedDescription
                AppState.shared.showError = true
                return
            }
            guard let library else { return }
            Task {
                for url in urls {
                    await library.addFolder(url)
                }
            }
        }
        #if os(iOS)
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        #endif
        .sheet(isPresented: $showAddTagSheet) {
            AddTagSheet(isPresented: $showAddTagSheet) { name, colorHex in
                addTag(name: name, colorHex: colorHex)
            }
        }
    }

    private func confirmDeletion(of books: Set<Book>) {
        guard !books.isEmpty else { return }
        booksPendingDeletion = books.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        showDeleteConfirmation = true
    }

    private func deleteBooks(_ books: [Book]) {
        booksPendingDeletion = []
        selection.subtract(books)
        // The reader may have moved on from the book it was opened with to a later volume
        if [navigationBook, readerBook].contains(where: { $0.map(books.contains) ?? false }) {
            navigationBook = nil
            readerBook = nil
        }
        #if os(iOS)
            if selection.isEmpty {
                editMode = .inactive
            }
        #endif
        // Delete in the same update that clears the selection; a later delete leaves the list
        // redrawing selected rows whose models are gone
        for book in books {
            modelContext.delete(book)
        }
        try? modelContext.save()
    }

    private func deleteTag(_ tag: Tag) {
        modelContext.delete(tag)
        try? modelContext.save()
    }

    private func addTag(name: String, colorHex: String) {
        let tag = Tag(name: name, colorHex: colorHex)
        modelContext.insert(tag)
        try? modelContext.save()
    }
}

struct BookRow: View {
    let book: Book

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            if let thumbnailData = book.thumbnailData,
               let thumbnail = PlatformImage(imageData: thumbnailData) {
                Image(platformImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 40, height: 56)
                    .clipped()
                    .cornerRadius(4)
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 40, height: 56)
                    .overlay {
                        Image(systemName: "book.closed")
                            .foregroundStyle(.secondary)
                    }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(book.title)
                    .font(.subheadline)
                    .lineLimit(2)

                if let progress = book.progress {
                    Text("\(progress.currentPage + 1) / \(book.totalPages)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationSplitView {
        SidebarView(columnVisibility: .constant(.all))
    } detail: {
        Text("Detail")
    }
    .modelContainer(for: [Book.self, Tag.self], inMemory: true)
}
