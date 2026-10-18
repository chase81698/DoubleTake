// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DoubleTake",
    platforms: [.macOS(.v15)],
    targets: [
        .target(
            name: "DoubleTakeCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "DoubleTake",
            dependencies: ["DoubleTakeCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "DoubleTakeCoreTests",
            dependencies: ["DoubleTakeCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
