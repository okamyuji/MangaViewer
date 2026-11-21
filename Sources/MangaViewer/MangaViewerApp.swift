import SwiftData
import SwiftUI

@main
struct MangaViewerApp: App {
    #if os(macOS)
        @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif
    @State private var appState = AppState.shared
    /// One library for every window, so a second window does not rescan and re-import the same folders
    @State private var library: LibraryViewModel
    private let sharedModelContainer: ModelContainer

    init() {
        let container = Self.makeModelContainer()
        sharedModelContainer = container
        // Unit tests are hosted by the app; keep them away from the real library and watched folders
        _library = State(initialValue: LibraryViewModel(
            modelContext: container.mainContext, startWatching: !AppEnvironment.isRunningUnitTests
        ))
    }

    private static func makeModelContainer() -> ModelContainer {
        let schema = Schema([
            Book.self,
            ReadingProgress.self,
            Bookmark.self,
            Tag.self
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema, isStoredInMemoryOnly: AppEnvironment.isRunningUnitTests || AppEnvironment.isRunningUITests
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .environment(library)
                .onOpenURL { url in
                    appState.openFile(url)
                }
        }
        .modelContainer(sharedModelContainer)

        #if os(macOS)
            Settings {
                SettingsView()
            }
        #endif
    }
}

#if os(macOS)
    final class AppDelegate: NSObject, NSApplicationDelegate {
        func application(_: NSApplication, open urls: [URL]) {
            for url in urls {
                Task { @MainActor in
                    AppState.shared.openFile(url)
                }
            }
        }

        func applicationDidFinishLaunching(_: Notification) {
            #if DEBUG
                // Command line argument file opening only works outside App Sandbox
                let args = CommandLine.arguments
                if args.count > 1 {
                    for arg in args.dropFirst() {
                        let url = URL(fileURLWithPath: arg)
                        if FileManager.default.fileExists(atPath: url.path) {
                            Task { @MainActor in
                                AppState.shared.openFile(url)
                            }
                            break
                        }
                    }
                }
            #endif
        }
    }
#endif

@Observable
@MainActor
final class AppState {
    static let shared = AppState()

    var fileToOpen: URL?
    var openError: String?
    var showError: Bool = false

    private init() {}

    func openFile(_ url: URL) {
        // Verify the file is a supported format
        guard ArchiveService.bookType(for: url) != nil else {
            openError = "Unsupported file format: \(url.pathExtension)"
            showError = true
            return
        }

        // No existence check here: a file-provider item may not be on the device until the
        // coordinated read in the opener downloads it, and the opener reports a missing file.

        fileToOpen = url
    }

    func clearFileToOpen() {
        fileToOpen = nil
    }
}
