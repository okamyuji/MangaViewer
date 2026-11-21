import Foundation

enum Constants {
    enum Thumbnail {
        static let width: CGFloat = 200
        static let height: CGFloat = 300
    }
}

enum AppEnvironment {
    /// Set by Xcode when the app hosts a unit-test bundle; UI tests launch the app without it.
    static let isRunningUnitTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
}
