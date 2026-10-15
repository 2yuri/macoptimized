// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacOptimized",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "MacOptimized",
            path: "Sources/MacOptimized",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(name: "MacOptimizedTests", dependencies: ["MacOptimized"]),
    ]
)
