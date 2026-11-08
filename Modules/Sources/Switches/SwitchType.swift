//
//  SwitchType.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/1.
//

import AppKit

public struct SwitchBarInfo {
    public let title: String
    public let onImage: NSImage?
    public let offImage: NSImage?
    public var controlType: ControlType = .Switch
    public var category: SwitchCategory = .none
    
    public init(
        title: String,
        onImage: NSImage? = nil,
        offImage: NSImage? = nil,
        controlType: ControlType = .Switch,
        category: SwitchCategory = .none
    ) {
        self.title = title
        self.onImage = onImage
        self.offImage = offImage
        self.controlType = controlType
        self.category = category
    }
}

public enum SwitchType: String, CaseIterable, Sendable {
    case hiddeDesktop
    case darkMode
    case topNotch
    case mute
    case keepAwake
    case screenSaver
    case nightShift
    case autohideDock
    case autohideMenuBar
    case airPods
    case bluetooth
    case xcodeCache
    case hiddenFiles
    case radioStation
    case emptyTrash
    case emptyPasteboard
    case showUserLibrary
    case showExtensionName
    case pomodoroTimer
    case smallLaunchpadIcon
    case lowpowerMode
    case muteMicrophone
    case showFinderPathbar
    case dockRecent
    case spotify
    case applemusic
    case screenTest
    case hideMenubarIcons
    case fkey
    case backNoises
    case dimScreen
    case ejectDiscs
    case hideWindows
    case trueTone
    case topSticker
    case keyLight
    case aiCommender
    case authenticator
    case soundMixer
    case desktopPet
    case codexUsage
    case reverseScrollDirection
    case systemMonitor
    case aphrodite
    case dockPreview
    case claudeUsage
    case xcodeCleaner
    case appUninstaller
    case tailscale

    public var legacyIdentifier: UInt64 {
        switch self {
        case .hiddeDesktop: 1
        case .darkMode: 2
        case .topNotch: 4
        case .mute: 8
        case .keepAwake: 16
        case .screenSaver: 32
        case .nightShift: 64
        case .autohideDock: 128
        case .autohideMenuBar: 256
        case .airPods: 512
        case .bluetooth: 1_024
        case .xcodeCache: 2_048
        case .hiddenFiles: 4_096
        case .radioStation: 8_192
        case .emptyTrash: 16_384
        case .emptyPasteboard: 32_768
        case .showUserLibrary: 65_536
        case .showExtensionName: 131_072
        case .pomodoroTimer: 262_144
        case .smallLaunchpadIcon: 524_288
        case .lowpowerMode: 1_048_576
        case .muteMicrophone: 2_097_152
        case .showFinderPathbar: 4_194_304
        case .dockRecent: 8_388_608
        case .spotify: 16_777_216
        case .applemusic: 33_554_432
        case .screenTest: 67_108_864
        case .hideMenubarIcons: 134_217_728
        case .fkey: 268_435_456
        case .backNoises: 536_870_912
        case .dimScreen: 1_073_741_824
        case .ejectDiscs: 2_147_483_648
        case .hideWindows: 4_294_967_296
        case .trueTone: 8_589_934_592
        case .topSticker: 17_179_869_184
        case .keyLight: 34_359_738_368
        case .aiCommender: 68_719_476_736
        case .authenticator: 137_438_953_472
        case .soundMixer: 274_877_906_944
        case .desktopPet: 549_755_813_888
        case .codexUsage: 1_099_511_627_776
        case .reverseScrollDirection: 2_199_023_255_552
        case .systemMonitor: 4_398_046_511_104
        case .aphrodite: 8_796_093_022_208
        case .dockPreview: 17_592_186_044_416
        case .claudeUsage: 35_184_372_088_832
        case .xcodeCleaner: 70_368_744_177_664
        case .appUninstaller: 140_737_488_355_328
        case .tailscale: 281_474_976_710_656
        }
    }

    public init?(legacyIdentifier: UInt64) {
        guard let type = Self.allCases.first(where: { $0.legacyIdentifier == legacyIdentifier }) else {
            return nil
        }
        self = type
    }
    
}

extension SwitchType {
    /// Switches that only showed or hid a popover tab. Tab visibility is managed on the Tabs settings page,
    /// so these cases stay for stored identifiers but are no longer offered as switches.
    public static let deprecatedTabVisibilitySwitches: Set<SwitchType> = [
        .authenticator, .soundMixer, .systemMonitor, .codexUsage,
        .claudeUsage, .aphrodite, .xcodeCleaner, .appUninstaller,
    ]

    public var isDeprecatedTabVisibilitySwitch: Bool {
        Self.deprecatedTabVisibilitySwitches.contains(self)
    }

    /// Built-in switches that can still be shown in the switch list, widgets and the remote catalog.
    public static var offeredCases: [SwitchType] {
        allCases.filter { !$0.isDeprecatedTabVisibilitySwitch }
    }
}

public let switchTypeCount = SwitchType.allCases.count

public enum ControlType: String, Codable, Sendable{
    case Switch
    case Button
    case Player
}

public enum SwitchCategory {
    case none
    case audio
    case cleanup
    case tool
}
