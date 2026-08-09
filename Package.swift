// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StorageLens",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "StorageLensKit", targets: ["StorageLensKit"]),
        .executable(name: "StorageLens", targets: ["StorageLens"]),
    ],
    targets: [
        .target(
            name: "StorageLensKit",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "StorageLens",
            dependencies: ["StorageLensKit"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "StorageLensKitTests",
            dependencies: ["StorageLensKit"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
