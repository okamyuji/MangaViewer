import SwiftUI

struct SettingsView: View {
    @State private var viewModel = SettingsViewModel()

    var body: some View {
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
        .frame(width: 450, height: 300)
    }

    private var generalSettings: some View {
        Form {
            Section {
                Text("MangaViewer")
                    .font(.headline)
                Text("A manga viewer for macOS")
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

                Picker("Display Mode", selection: $viewModel.displayMode) {
                    ForEach(DisplayMode.allCases) { mode in
                        Text(mode.label).tag(mode)
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
                            viewModel.removeWatchedFolder(folder)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Button("Add Folder...") {
                    addWatchedFolder()
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func addWatchedFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            viewModel.addWatchedFolder(url)
        }
    }
}

#Preview {
    SettingsView()
}
