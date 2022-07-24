//
//  SwitchType.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/1.
//

import AppKit

struct SwitchBarInfo {
    let title:String
    let onImage:NSImage?
    let offImage:NSImage?
    var controlType:ControlType = .Switch
    var category:SwitchCategory = .none
}

enum SwitchType:UInt64, CaseIterable {
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
    case emptyTrash = 16384 // 1 << 14
    case emptyPasteboard = 32768 // 1 << 15
    case showUserLibrary = 65536 // 1 << 16
    case showExtensionName = 131072 // 1 << 17
    case pomodoroTimer = 262144 // 1 << 18
    case smallLaunchpadIcon = 524288 // 1 << 19
    case lowpowerMode = 1048576 // 1 << 20
    case muteMicrophone = 2097152 // 1 << 21
    case showFinderPathbar = 4194304 // 1 << 22
    case dockRecent = 8388608 // 1 << 23
    case spotify = 16777216 // 1 << 24
    case applemusic = 33554432 // 1 << 25
    case screenTest = 67108864 // 1 << 26
    case hideMenubarIcons = 134217728 // 1 << 27
    
        
}

let switchTypeCount = SwitchType.allCases.count

enum ControlType{
    case Switch
    case Button
}

enum SwitchCategory{
    case none
    case audio
    case cleanup
    case tool
}


