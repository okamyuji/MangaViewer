import SwiftUI

struct BookGridItem: View {
    let book: Book
    let onOpen: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            thumbnailView
                .frame(width: Constants.Thumbnail.width, height: Constants.Thumbnail.height)
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .topTrailing) {
                    if book.progress?.isCompleted == true {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .padding(4)
                    }
                }
                .shadow(radius: 2)

            VStack(spacing: 2) {
                Text(book.title)
                    .font(.caption)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                if let progress = book.progress, progress.currentPage > 0 {
                    Text("\(progress.currentPage + 1) / \(book.totalPages)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: Constants.Thumbnail.width)
        }
        .onTapGesture(count: 2) {
            onOpen()
        }
        .contextMenu {
            Button("Open") {
                onOpen()
            }

            Button("Show in Finder") {
                let url = URL(fileURLWithPath: book.filePath)
                NSWorkspace.shared.selectFile(
                    url.path,
                    inFileViewerRootedAtPath: url.deletingLastPathComponent().path
                )
            }

            Divider()

            Button("Delete", role: .destructive) {
                // Handle deletion through parent view
            }
        }
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if let thumbnailData = book.thumbnailData,
           let nsImage = NSImage(data: thumbnailData) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            Image(systemName: "book.closed")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    BookGridItem(
        book: Book(title: "Sample Manga", filePath: "/path/to/manga.cbz", type: .cbz, totalPages: 100),
        onOpen: {}
    )
    .padding()
}
