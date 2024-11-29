// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "PersistentKeyValueKit",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
        .tvOS(.v15),
        .visionOS(.v1),
        .watchOS(.v8),
    ],
    products: [
        .library(
            name: "PersistentKeyValueKit",
            targets: [
                "PersistentKeyValueKit",
            ]
        ),
    ],
    targets: [
        .target(
            name: "PersistentKeyValueKit"
        ),
        .testTarget(
            name: "PersistentKeyValueKitTests",
            dependencies: [
                "PersistentKeyValueKit",
            ]
        ),
    ]
)
