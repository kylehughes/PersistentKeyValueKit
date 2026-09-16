// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "PersistentKeyValueKit",
    platforms: [
        .iOS(.v15),
        .macOS(.v13),
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
            name: "PersistentKeyValueKit",
            swiftSettings: [
                .treatAllWarnings(as: .error),
            ]
        ),
        .testTarget(
            name: "PersistentKeyValueKitTests",
            dependencies: [
                "PersistentKeyValueKit",
            ],
            swiftSettings: [
                .treatAllWarnings(as: .error),
            ]
        ),
        .testTarget(
            name: "PersistentKeyValueKitPublicAPITests",
            dependencies: [
                "PersistentKeyValueKit",
            ],
            path: "Tests/PersistentKeyValueKitPublicAPITests",
            swiftSettings: [
                .treatAllWarnings(as: .error),
            ]
        ),
    ]
)
