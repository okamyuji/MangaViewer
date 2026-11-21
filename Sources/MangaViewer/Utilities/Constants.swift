import Foundation

enum Constants {
    /// Bounds on untrusted archive input, so a decompression bomb cannot exhaust memory.
    enum Limits {
        /// Largest page an archive may inflate to; real manga pages are a few megabytes.
        static let maxPageBytes: Int64 = 128 * 1024 * 1024
        /// Images with more pixels are decoded downscaled (50 MP is about 8700 x 5800).
        static let maxImagePixels = 50_000_000
    }

    enum Thumbnail {
        static let width: CGFloat = 200
        static let height: CGFloat = 300
    }
}

enum AppEnvironment {
    /// Set by Xcode when the app hosts a unit-test bundle; UI tests launch the app without it.
    static let isRunningUnitTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    #if DEBUG
        /// UI tests launch the app with a `-UITest…` argument; they get a throwaway library too.
        static let isRunningUITests = ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("-UITest") }
    #else
        static let isRunningUITests = false
    #endif
}
