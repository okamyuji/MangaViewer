import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @State private var viewModel = SettingsViewModel()
    @State private var showFolderImporter = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        #if os(macOS)
            tabs
                .frame(width: 450, height: 300)
        #else
            NavigationStack {
                tabs
                    .navigationTitle("Settings")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { dismiss() }
                        }
                    }
            }
        #endif
    }

    private var tabs: some View {
        TabView {
            generalSettings
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            readingSettings
                .tabItem {
                    Label("Reading", systemImage: "book")
                }

            librarySettings
                .tabItem {
                    Label("Library", systemImage: "folder")
                }
        }
        .fileImporter(isPresented: $showFolderImporter, allowedContentTypes: [.folder]) { result in
            switch result {
            case let .success(url):
                Task {
                    if await !viewModel.addWatchedFolder(url) {
                        AppState.shared.openError =
                            "Could not keep access to \(url.lastPathComponent). Choose the folder again."
                        AppState.shared.showError = true
                    }
                }
            case let .failure(error):
                AppState.shared.openError = error.localizedDescription
                AppState.shared.showError = true
            }
        }
    }

    private var generalSettings: some View {
        Form {
            Section {
                Text("MangaViewer")
                    .font(.headline)
                Text("A manga viewer for macOS and iPad")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var readingSettings: some View {
        Form {
            Section("Default Settings") {
                Picker("Reading Direction", selection: $viewModel.readingDirection) {
                    ForEach(ReadingDirection.allCases) { direction in
                        Text(direction.label).tag(direction)
                    }
                }

                Picker("Zoom Mode", selection: $viewModel.zoomMode) {
                    ForEach(ZoomMode.allCases.filter { $0 != .custom }) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var librarySettings: some View {
        Form {
            Section("Watched Folders") {
                ForEach(viewModel.watchedFolders, id: \.self) { folder in
                    HStack {
                        Image(systemName: "folder")
                        Text(folder.path)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button {
                            Task {
                                await viewModel.removeWatchedFolder(folder)
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Button("Add Folder...") {
                    showFolderImporter = true
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

#Preview {
    SettingsView()
}
