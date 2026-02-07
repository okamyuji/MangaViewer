import SwiftData
import SwiftUI

struct SidebarView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Book.title) private var books: [Book]
    @Query(sort: \Tag.name) private var tags: [Tag]

    @State private var searchText = ""
    @State private var sortOrder: SortOrder = .title
    @State private var selectedBook: Book?
    @State private var navigationBook: Book?
    @State private var showAddTagSheet = false
    @State private var selectedTag: Tag?

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
            result.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
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

            List(selection: $selectedBook) {
                // Library Section with books
                Section("Library") {
                    ForEach(filteredBooks) { book in
                        BookRow(book: book)
                            .tag(book)
                            .contextMenu {
                                Button("Delete", role: .destructive) {
                                    deleteBook(book)
                                }
                            }
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
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    importBooks()
                } label: {
                    Image(systemName: "plus")
                }
                .help("Add Books")
            }

            ToolbarItem(placement: .primaryAction) {
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
            ReaderView(book: book)
                .id(book.id)
        }
        .onChange(of: selectedBook) { _, newBook in
            if let book = newBook {
                // Reset navigation first to ensure it triggers even for the same book
                navigationBook = nil
                Task { @MainActor in
                    navigationBook = book
                }
            }
        }
        .sheet(isPresented: $showAddTagSheet) {
            AddTagSheet(isPresented: $showAddTagSheet) { name, colorHex in
                addTag(name: name, colorHex: colorHex)
            }
        }
    }

    private func deleteBook(_ book: Book) {
        Task {
            await SecurityScopedBookmarkManager.shared.removeBookmark(for: book.filePath)
        }
        modelContext.delete(book)
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

    private func importBooks() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.zip, .data, .folder]

        panel.begin { response in
            guard response == .OK else { return }

            Task { @MainActor in
                let viewModel = LibraryViewModel(modelContext: modelContext)
                for url in panel.urls {
                    await viewModel.addFolder(url)
                }
            }
        }
    }
}

struct BookRow: View {
    let book: Book

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            if let thumbnailData = book.thumbnailData,
               let thumbnail = NSImage(data: thumbnailData) {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
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
        SidebarView()
    } detail: {
        Text("Detail")
    }
    .modelContainer(for: [Book.self, Tag.self], inMemory: true)
}
