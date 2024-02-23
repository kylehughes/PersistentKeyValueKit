// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "KeyValueKit",
    platforms: [
        .iOS(.v13),
        .watchOS(.v7),
    ],
    products: [
        .library(
            name: "KeyValueKit",
            targets: [
                "KeyValueKit",
            ]
        ),
    ],
    targets: [
        .target(
            name: "KeyValueKit"
        ),
        .testTarget(
            name: "KeyValueKitTests",
            dependencies: [
                "KeyValueKit",
            ]
        ),
    ]
)
