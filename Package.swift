// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MangaViewer",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MangaViewer", targets: ["MangaViewer"])
    ],
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.0"),
        .package(url: "https://github.com/mtgto/Unrar.swift.git", from: "0.3.0")
    ],
    targets: [
        .executableTarget(
            name: "MangaViewer",
            dependencies: [
                "ZIPFoundation",
                .product(name: "Unrar", package: "Unrar.swift")
            ],
            path: "Sources/MangaViewer",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "MangaViewerTests",
            dependencies: ["MangaViewer"],
            path: "Tests/MangaViewerTests"
        )
    ]
)
