// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Modules",
    platforms: [
        .macOS(.v14)
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
            name: "Networking",
            targets: ["Networking"]
        ),
        .library(
            name: "OnlyAgent",
            targets: ["OnlyAgent"]
        ),
        .library(
            name: "PureColorView",
            targets: ["PureColorView"]
        ),
        .library(
            name: "StickerView",
            targets: ["StickerView"]
        ),
        .library(
            name: "Authenticator",
            targets: ["Authenticator"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", exact: "1.25.3"),
        .package(url: "https://github.com/pointfreeco/swift-sharing", exact: "2.8.0"),
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", exact: "2.3.1"),
        .package(url: "https://github.com/Alamofire/Alamofire", exact: "5.5.0"),
        .package(url: "https://github.com/siteline/swiftui-introspect", from: "26.0.0"),
        .package(url: "https://github.com/lzell/AIProxySwift", exact: "0.146.0"),
        .package(url: "https://github.com/firebase/firebase-ios-sdk", exact: "12.6.0"),
        .package(url: "https://github.com/jacklandrin/ollama-swift", revision: "04a5730fa8aace6fcca8a1cebb83562cfe7dee06"),
        .package(url: "https://github.com/timazed/CodexKit", revision: "85c410cc1f3adfd256c7e43bbe978ce892b27408")
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
            name: "Networking",
            dependencies: [
                .product(name: "Alamofire", package: "Alamofire")
            ]
        ),
        .target(
            name: "OnlyAgent",
            dependencies: [
                .product(name: "SwiftUIIntrospect", package: "swiftui-introspect"),
                .product(name: "Alamofire", package: "Alamofire"),
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "Sharing", package: "swift-sharing"),
                .product(name: "AIProxy", package: "AIProxySwift"),
                .product(name: "FirebaseAILogic", package: "firebase-ios-sdk"),
                .product(name: "Ollama", package: "ollama-swift"),
                .product(name: "CodexKit", package: "CodexKit"),
                "Extensions",
                "Defines",
                "Design",
                "Networking"
            ],
            resources: [
                .process("Resources")
            ]
        ),
        .target(
            name: "PureColorView",
            dependencies: [
                "Extensions"
            ]
        ),
        .target(
            name: "StickerView",
            dependencies: [
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
                .product(name: "Sharing", package: "swift-sharing"),
                "Defines",
                "Extensions"
            ]
        ),
        .target(
            name: "Authenticator",
            dependencies: [
                "Defines",
                "Extensions",
                "Utilities"
            ]
        ),
        .testTarget(
            name: "ModulesTests",
            dependencies: [
                "Authenticator",
                "OnlyControl",
                "OnlyAgent",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture")
            ]
        )
    ]
)
