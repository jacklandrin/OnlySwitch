// swift-tools-version: 5.10
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
        ),
        .library(
            name: "Design",
            targets: ["Design"]
        ),
        .library(
            name: "OnlyAgent",
            targets: ["OnlyAgent"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", exact: "1.20.2"),
        .package(url: "https://github.com/pointfreeco/swift-sharing", exact: "2.7.4"),
        .package(url: "https://github.com/Alamofire/Alamofire", exact: "5.5.0"),
        .package(url: "https://github.com/siteline/swiftui-introspect", from: "26.0.0"),
        .package(url: "https://github.com/MacPaw/OpenAI.git", exact: "0.4.7"),
        .package(url: "https://github.com/firebase/firebase-ios-sdk.git", exact: "12.6.0")
    ],
    targets: [
        .target(
            name: "Extensions",
            dependencies: [
                "Defines",
                .product(name: "Sharing", package: "swift-sharing")
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
        .target(name: "Reorderable"),
        .target(name: "Design"),
        .target(
            name: "OnlyAgent",
            dependencies: [
                .product(name: "SwiftUIIntrospect", package: "swiftui-introspect"),
                .product(name: "Alamofire", package: "Alamofire"),
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "Sharing", package: "swift-sharing"),
                .product(name: "OpenAI", package: "OpenAI"),
                .product(name: "FirebaseAILogic", package: "firebase-ios-sdk"),
                "Extensions",
                "Defines",
                "Design"
            ],
            resources: [
                .process("Resources")
            ]
        )
    ]
)
