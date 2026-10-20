// swift-tools-version: 6.0
// PaperSaver: programmatic control of the macOS wallpaper and screensaver selection.

import PackageDescription

let package = Package(
    name: "PaperSaver",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "PaperSaverKit",
            targets: ["PaperSaverKit"]
        ),
        .executable(
            name: "papersaver",
            targets: ["PaperSaverCLI"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.8.2"),
    ],
    targets: [
        .target(
            name: "PaperSaverKit"
        ),
        .executableTarget(
            name: "PaperSaverCLI",
            dependencies: [
                "PaperSaverKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "PaperSaverTests",
            dependencies: ["PaperSaverKit"],
            resources: [.copy("Fixtures")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
