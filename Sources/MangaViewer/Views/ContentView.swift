import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var books: [Book]

    var body: some View {
        NavigationSplitView {
            TagSidebar()
        } content: {
            LibraryView()
        } detail: {
            Text("Select a book to read")
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 900, minHeight: 600)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Book.self, inMemory: true)
}
