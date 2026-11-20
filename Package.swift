// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "PersistentKeyValueKit",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
        .tvOS(.v16),
        .visionOS(.v1),
        .watchOS(.v9),
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
            resources: [
                .process("PrivacyInfo.xcprivacy"),
            ],
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
