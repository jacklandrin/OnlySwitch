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

public enum SwitchType:UInt64, CaseIterable {
    case hiddeDesktop = 1 //1 << 0
    case darkMode = 2 // 1 << 1
    case topNotch = 4 // 1 << 2
    case mute = 8 // 1 << 3
    case keepAwake = 16 // 1 << 4
    case screenSaver = 32 // 1 << 5
    case nightShift = 64 // 1 << 6
    case autohideDock = 128 // 1 << 7
    case autohideMenuBar = 256 // 1 << 8
    case airPods = 512 // 1 << 9
    case bluetooth = 1024 // 1 << 10
    case xcodeCache = 2048 // 1 << 11
    case hiddenFiles = 4096 // 1 << 12
    case radioStation = 8192 // 1 << 13
    case emptyTrash = 16_384 // 1 << 14
    case emptyPasteboard = 32_768 // 1 << 15
    case showUserLibrary = 65_536 // 1 << 16
    case showExtensionName = 131_072 // 1 << 17
    case pomodoroTimer = 262_144 // 1 << 18
    case smallLaunchpadIcon = 524_288 // 1 << 19
    case lowpowerMode = 1_048_576 // 1 << 20
    case muteMicrophone = 2_097_152 // 1 << 21
    case showFinderPathbar = 4_194_304 // 1 << 22
    case dockRecent = 8_388_608 // 1 << 23
    case spotify = 16_777_216 // 1 << 24
    case applemusic = 33_554_432 // 1 << 25
    case screenTest = 67_108_864 // 1 << 26
    case hideMenubarIcons = 134_217_728 // 1 << 27
    case fkey = 268_435_456 // 1 << 28
    case backNoises = 536_870_912 // 1 << 29
    case dimScreen = 1_073_741_824 // 1 << 30
    case ejectDiscs = 2_147_483_648 // 1 << 31
    case hideWindows = 4_294_967_296 // 1 << 32
    case trueTone = 8_589_934_592 // 1 << 33
    case topSticker = 17_179_869_184 // 1 << 34
}

public let switchTypeCount = SwitchType.allCases.count

public enum ControlType: String, Codable{
    case Switch
    case Button
    case Player
}

public enum SwitchCategory{
    case none
    case audio
    case cleanup
    case tool
}


