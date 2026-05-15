// SPDX-License-Identifier: MIT
// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "HyperliquidAPI",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "HyperliquidAPI",
            targets: ["HyperliquidAPI"]
        )
    ],
    dependencies: [
        .package(path: "../OpenHLCore")
    ],
    targets: [
        .target(
            name: "HyperliquidAPI",
            dependencies: ["OpenHLCore"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "HyperliquidAPITests",
            dependencies: ["HyperliquidAPI", "OpenHLCore"],
            resources: [
                .copy("Fixtures")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
    ]
)
