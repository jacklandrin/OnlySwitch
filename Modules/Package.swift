// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Modules",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "Extensions",
            targets: ["Extensions"]),
        .library(
            name: "Defines",
            targets: ["Defines"]),
        .library(
            name: "Switches",
            targets: ["Switches"]
        ),
        .library(
            name: "Utilities",
            targets: ["Utilities"]
        ),
        .library(
            name: "OnlyControl",
            targets: ["OnlyControl"]
        ),
        .library(
            name: "Reorderable",
            targets: ["Reorderable"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", exact: "1.13.1"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.0.0" )
    ],
    targets: [
        .target(
            name: "Extensions",
            dependencies: [
                "Defines"
            ]),
        .target(
            name: "Defines"
        ),
        .target(
            name: "Switches",
            dependencies: [
                "Extensions"
            ],
            resources: [
                .process("Resources")
            ]
        ),
        .target(
            name: "Utilities",
            dependencies: [
                "Extensions",
                "Defines"
            ]
        ),
        .target(
            name: "OnlyControl",
            dependencies: [
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                "Extensions",
                "Defines",
                "Switches",
                "Utilities",
                "Reorderable"
            ]
        ),
        .target(name: "Reorderable")
    ]
)
