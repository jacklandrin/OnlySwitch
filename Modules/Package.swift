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
        )
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
        )
    ]
)
