// SPDX-License-Identifier: MIT
// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "OpenHLCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "OpenHLCore",
            targets: ["OpenHLCore"]
        )
    ],
    targets: [
        .target(
            name: "OpenHLCore",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "OpenHLCoreTests",
            dependencies: ["OpenHLCore"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
    ]
)
