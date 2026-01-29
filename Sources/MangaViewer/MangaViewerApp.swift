import SwiftData
import SwiftUI

@main
struct MangaViewerApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
  @State private var appState = AppState.shared

  var sharedModelContainer: ModelContainer = {
    let schema = Schema([
      Book.self,
      ReadingProgress.self,
      Bookmark.self,
      Tag.self,
    ])
    let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

    do {
      return try ModelContainer(for: schema, configurations: [modelConfiguration])
    } catch {
      fatalError("Could not create ModelContainer: \(error)")
    }
  }()

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environment(appState)
        .onOpenURL { url in
          appState.openFile(url)
        }
    }
    .modelContainer(sharedModelContainer)

    Settings {
      SettingsView()
    }
  }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
  func application(_ application: NSApplication, open urls: [URL]) {
    for url in urls {
      Task { @MainActor in
        AppState.shared.openFile(url)
      }
    }
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    // Check command line arguments for file paths
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
  }
}

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

    // Verify the file exists
    guard FileManager.default.fileExists(atPath: url.path) else {
      openError = "File not found: \(url.lastPathComponent)"
      showError = true
      return
    }

    fileToOpen = url
  }

  func clearFileToOpen() {
    fileToOpen = nil
  }
}
