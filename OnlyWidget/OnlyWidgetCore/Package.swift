// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "OnlyWidgetCore",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "OnlyWidgetCore",
            targets: ["OnlyWidgetCore"]),
    ],
    dependencies: [
        .package(name: "Modules", path: "../../Modules")
        ],
    targets: [
        .target(
            name: "OnlyWidgetCore"),
        .testTarget(
            name: "OnlyWidgetCoreTests",
            dependencies: ["OnlyWidgetCore"]),
    ]
)
