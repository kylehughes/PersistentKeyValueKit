// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "PersistentKeyValueKit",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15),
        .watchOS(.v7),
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
