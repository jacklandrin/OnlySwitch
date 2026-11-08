// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Modules",
    platforms: [
        .macOS(.v14),
        .iOS(.v18)
    ],
    products: [
        .library(name: "SoundMixerEQ", targets: ["SoundMixerEQ"]),
        .library(name: "DisplayDDC", targets: ["DisplayDDC"]),
        .library(name: "DisplayBrightness", targets: ["DisplayBrightness"]),
        .library(name: "Tailscale", targets: ["Tailscale"]),
        .library(name: "XcodeCleaner", targets: ["XcodeCleaner"]),
        .library(name: "AppUninstaller", targets: ["AppUninstaller"]),
        .library(name: "Screenshots", targets: ["Screenshots"]),
        .library(name: "RadioBrowser", targets: ["RadioBrowser"]),
        .library(name: "Scheduler", targets: ["Scheduler"]),
        .library(name: "OnlySwitchObjC", targets: ["OnlySwitchObjC"]),
        .library(name: "OnlySwitchPersistence", targets: ["OnlySwitchPersistence"]),
        .library(name: "PrivilegedHelperCore", targets: ["PrivilegedHelperCore"]),
        .library(name: "AppFeature", targets: ["AppFeature"]),
        .library(name: "OnlyRemoteFeature", targets: ["OnlyRemoteFeature"]),
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
            name: "Aphrodite",
            targets: ["Aphrodite"]
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
        ),
        .library(
            name: "DesktopPet",
            targets: ["DesktopPet"]
        ),
        .library(
            name: "RemoteCore",
            targets: ["RemoteCore"]
        ),
        .library(
            name: "RemoteTransport",
            targets: ["RemoteTransport"]
        ),
        .library(
            name: "SystemMonitor",
            targets: ["SystemMonitor"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.9.2"),
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", exact: "1.26.2"),
        .package(url: "https://github.com/pointfreeco/swift-sharing", exact: "2.10.0"),
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", exact: "2.3.1"),
        .package(url: "https://github.com/Alamofire/Alamofire", exact: "5.5.0"),
        .package(url: "https://github.com/siteline/swiftui-introspect", from: "26.0.0"),
        .package(url: "https://github.com/lzell/AIProxySwift", exact: "0.146.0"),
        .package(url: "https://github.com/firebase/firebase-ios-sdk", exact: "12.6.0"),
        .package(url: "https://github.com/jacklandrin/ollama-swift", revision: "04a5730fa8aace6fcca8a1cebb83562cfe7dee06"),
        .package(url: "https://github.com/timazed/CodexKit", revision: "85c410cc1f3adfd256c7e43bbe978ce892b27408"),
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
        .package(url: "https://github.com/sindresorhus/LaunchAtLogin", exact: "5.0.2"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", exact: "3.1.0"),
        .package(url: "https://github.com/elai950/AlertToast.git", exact: "1.3.9"),
        .package(url: "https://github.com/globulus/swiftui-webview", exact: "1.0.8"),
        .package(url: "https://github.com/pointfreeco/swift-custom-dump", from: "1.3.3")
    ],
    targets: [
        .target(
            name: "OnlySwitchObjC",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("IOBluetooth"),
                .linkedFramework("CoreDisplay"),
                .unsafeFlags([
                    "-F/System/Library/PrivateFrameworks",
                    "-framework", "DisplayServices",
                    "-framework", "CoreBrightness"
                ])
            ]
        ),
        .target(
            name: "OnlySwitchPersistence",
            dependencies: ["Extensions", "Defines"],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "OnlySwitchPersistenceTests", dependencies: ["OnlySwitchPersistence"]),
        .target(name: "PrivilegedHelperCore"),
        .target(
            name: "AppFeature",
            dependencies: [
                "Aphrodite", "AppUninstaller", "Authenticator", "Defines", "Design", "DesktopPet",
                "DisplayBrightness", "DisplayDDC", "Extensions", "Networking", "OnlyAgent", "OnlyControl",
                "OnlySwitchObjC", "OnlySwitchPersistence", "PrivilegedHelperCore", "PureColorView",
                "RadioBrowser", "RemoteCore", "RemoteTransport", "Scheduler", "Screenshots",
                "SoundMixerEQ", "StickerView", "Switches", "SystemMonitor", "Tailscale", "Utilities",
                "XcodeCleaner",
                .product(name: "Alamofire", package: "Alamofire"),
                .product(name: "AlertToast", package: "AlertToast"),
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "CustomDump", package: "swift-custom-dump"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
                .product(name: "LaunchAtLogin", package: "LaunchAtLogin"),
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "SwiftUIWebView", package: "swiftui-webview")
            ],
            exclude: [
                "Player/MusicAppPlayer/Spotify/SpotifyBridge/ObjC",
                "Player/MusicAppPlayer/AppleMusic/iTunesBridge/ObjC"
            ],
            swiftSettings: [.unsafeFlags(["-enforce-exclusivity=unchecked"])]
        ),
        .testTarget(
            name: "AppFeatureTests",
            dependencies: [
                "AppFeature", "Aphrodite", "Defines", "DesktopPet", "DisplayBrightness", "Extensions",
                "OnlyAgent", "OnlyControl", "OnlySwitchObjC", "OnlySwitchPersistence", "PrivilegedHelperCore",
                "RemoteCore", "RemoteTransport", "Screenshots", "SoundMixerEQ", "Switches", "SystemMonitor",
                "Tailscale", "Utilities",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "CustomDump", package: "swift-custom-dump"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts")
            ],
            exclude: [
                // Never members of the old OnlySwitchTests Xcode target; kept out to preserve the suite.
                "CodexUsageIntegrationTests.swift",
                "EverySwitchTests.swift",
                "OnlySwitchListSectionTests.swift",
                "SystemMonitor/SystemMonitorLocalizationTests.swift"
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "OnlyRemoteFeature",
            dependencies: [
                "RemoteCore", "RemoteTransport",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "DependenciesMacros", package: "swift-dependencies"),
                .product(name: "Sharing", package: "swift-sharing")
            ]
        ),
        .testTarget(
            name: "OnlyRemoteFeatureTests",
            dependencies: [
                "OnlyRemoteFeature", "RemoteCore", "RemoteTransport",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "Dependencies", package: "swift-dependencies")
            ]
        ),
        .target(name: "CSoundMixerEQ"),
        .target(name: "SoundMixerEQ", dependencies: ["CSoundMixerEQ", .product(name: "ComposableArchitecture", package: "swift-composable-architecture"), .product(name: "Dependencies", package: "swift-dependencies")]),
        .target(name: "DisplayDDC"),
        .target(name: "DisplayBrightness", dependencies: ["Extensions", .product(name: "ComposableArchitecture", package: "swift-composable-architecture"), .product(name: "Dependencies", package: "swift-dependencies")]),
        .testTarget(name: "DisplayBrightnessTests", dependencies: ["DisplayBrightness", .product(name: "ComposableArchitecture", package: "swift-composable-architecture")]),
        .testTarget(name: "DisplayDDCTests", dependencies: ["DisplayDDC"]),
        .testTarget(name: "SoundMixerEQTests", dependencies: ["SoundMixerEQ", "CSoundMixerEQ", .product(name: "ComposableArchitecture", package: "swift-composable-architecture")]),
        .target(name: "Tailscale", dependencies: ["Extensions", .product(name: "ComposableArchitecture", package: "swift-composable-architecture"), .product(name: "Dependencies", package: "swift-dependencies")]),
        .testTarget(name: "TailscaleTests", dependencies: ["Tailscale", "Switches", .product(name: "ComposableArchitecture", package: "swift-composable-architecture")]),
        .target(name: "AppUninstaller", dependencies: ["Extensions", .product(name: "ComposableArchitecture", package: "swift-composable-architecture"), .product(name: "Dependencies", package: "swift-dependencies")]),
        .testTarget(name: "AppUninstallerTests", dependencies: ["AppUninstaller", .product(name: "ComposableArchitecture", package: "swift-composable-architecture")]),
        .target(name: "Screenshots", dependencies: ["Extensions", .product(name: "ComposableArchitecture", package: "swift-composable-architecture"), .product(name: "Dependencies", package: "swift-dependencies")]),
        .testTarget(name: "ScreenshotsTests", dependencies: ["Screenshots", .product(name: "ComposableArchitecture", package: "swift-composable-architecture")]),
        .target(name: "RadioBrowser", dependencies: ["Extensions", .product(name: "ComposableArchitecture", package: "swift-composable-architecture"), .product(name: "Dependencies", package: "swift-dependencies")]),
        .testTarget(name: "RadioBrowserTests", dependencies: ["RadioBrowser", .product(name: "ComposableArchitecture", package: "swift-composable-architecture")]),
        .target(name: "Scheduler", dependencies: ["Extensions", "RemoteCore", .product(name: "ComposableArchitecture", package: "swift-composable-architecture"), .product(name: "Dependencies", package: "swift-dependencies")]),
        .testTarget(name: "SchedulerTests", dependencies: ["Scheduler", "RemoteCore", .product(name: "ComposableArchitecture", package: "swift-composable-architecture")]),
        .target(name: "XcodeCleaner", dependencies: ["Extensions", .product(name: "Dependencies", package: "swift-dependencies"), .product(name: "ComposableArchitecture", package: "swift-composable-architecture")]),
        .testTarget(name: "XcodeCleanerTests", dependencies: ["XcodeCleaner", .product(name: "ComposableArchitecture", package: "swift-composable-architecture")]),
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
                "Authenticator",
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
            name: "Aphrodite",
            dependencies: [
                .product(name: "SwiftUIIntrospect", package: "swiftui-introspect"),
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                "OnlyAgent",
                "RemoteCore",
                "Defines",
                "Extensions"
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
        .target(
            name: "DesktopPet",
            dependencies: [
                "Design",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture")
            ]
        ),
        .target(
            name: "RemoteCore"
        ),
        .target(
            name: "RemoteTransport",
            dependencies: ["RemoteCore"]
        ),
        .target(
            name: "SystemMonitor",
            dependencies: [
                "RemoteCore",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture")
            ]
        ),
        .testTarget(
            name: "ModulesTests",
            dependencies: [
                "Extensions",
                "Switches",
                "Authenticator",
                "DesktopPet",
                "OnlyControl",
                "OnlyAgent",
                "Aphrodite",
                "Networking",
                "RemoteCore",
                "RemoteTransport",
                "SystemMonitor",
                "StickerView",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture")
            ]
        )
    ]
)
