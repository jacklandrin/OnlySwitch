//
//  SwitchType.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/1.
//

import AppKit

struct SwitchBarInfo {
    let title:String
    let onImage:NSImage
    let offImage:NSImage
    var controlType:ControlType = .Switch
}

enum SwitchType:UInt64, CaseIterable {
    case hiddeDesktop = 1
    case darkMode = 2
    case topNotch = 4
    case mute = 8
    case keepAwake = 16
    case screenSaver = 32
    case nightShift = 64
    case autohideDock = 128
    case autohideMenuBar = 256
    case airPods = 512
    case bluetooth = 1024
    case xcodeCache = 2048
    case hiddenFiles = 4096
    case radioStation = 8192
    case emptyTrash = 16384
    case emptyPasteboard = 32768
    case showUserLibrary = 65536
    case showExtensionName = 131072
    case pomodoroTimer = 262144
    case smallLaunchpadIcon = 524288
    case lowpowerMode = 1048576
    
    func barInfo() -> SwitchBarInfo {
        switch self {
        case .hiddeDesktop:
            return SwitchBarInfo(title:"Hide Desktop",
                                 onImage:NSImage(named: "desktopcomputer")!,
                                 offImage:NSImage(named: "desktop_with_icon")!)
        case .darkMode:
            return SwitchBarInfo(title:"Dark Mode",
                                 onImage:NSImage(named: "darkmode_on")!,
                                 offImage: NSImage(named: "darkmode_off")!)
        case .topNotch:
            return SwitchBarInfo(title:"Hide Notch",
                                 onImage:NSImage(named:"laptopnotchhidden")!,
                                 offImage: NSImage(named: "laptopwithnotch")!)
        case .mute:
            return SwitchBarInfo(title: "Mute",
                                 onImage: NSImage(systemSymbolName: "speaker.slash.circle"),
                                 offImage: NSImage(systemSymbolName: "speaker.wave.2.circle"))
        case .keepAwake:
            return SwitchBarInfo(title: "Keep Awake",
                                onImage: NSImage(systemSymbolName: "lock.slash.fill"),
                                offImage: NSImage(systemSymbolName: "lock.slash"))
        case .screenSaver:
            return SwitchBarInfo(title: "Screen Saver",
                                 onImage: NSImage(systemSymbolName: "display"),
                                 offImage: NSImage(systemSymbolName: "display"))
        case .nightShift:
            return SwitchBarInfo(title: "Night Shift",
                                 onImage: NSImage(systemSymbolName: "moon.stars.fill"),
                                 offImage: NSImage(systemSymbolName: "moon.stars"))
        case .autohideDock:
            return SwitchBarInfo(title: "Autohide Dock",
                                 onImage: NSImage(systemSymbolName: "dock.arrow.down.rectangle"),
                                 offImage: NSImage(systemSymbolName: "dock.rectangle"))
        case .autohideMenuBar:
            return SwitchBarInfo(title: "Autohide Menu Bar",
                                 onImage: NSImage(systemSymbolName: "menubar.arrow.up.rectangle"),
                                 offImage: NSImage(systemSymbolName: "menubar.rectangle"))
        case .airPods:
            return SwitchBarInfo(title: "AirPods",
                                 onImage: NSImage(systemSymbolName: "airpodspro"),
                                 offImage: NSImage(systemSymbolName: "airpodspro"))
        case .bluetooth:
            return SwitchBarInfo(title: "Bluetooth",
                                 onImage: NSImage(named: "bluetooth_on")!,
                                 offImage: NSImage(named: "bluetooth_off")!)
        case .xcodeCache:
            return SwitchBarInfo(title: "Xcode Derived Data",
                                 onImage: NSImage(systemSymbolName: "hammer.circle.fill"),
                                 offImage: NSImage(systemSymbolName: "hammer.circle"),
                                 controlType: .Button)
        case .hiddenFiles:
            return SwitchBarInfo(title: "Show Hidden Files",
                                 onImage: NSImage(systemSymbolName: "eye"),
                                 offImage: NSImage(systemSymbolName: "eye.slash"))
        case .radioStation:
            return SwitchBarInfo(title: "Radio Player",
                                 onImage: NSImage(systemSymbolName: "radio"),
                                 offImage: NSImage(systemSymbolName: "radio"))
        case .emptyTrash:
            return SwitchBarInfo(title: "Empty Trash",
                                 onImage: NSImage(systemSymbolName: "trash"),
                                 offImage: NSImage(systemSymbolName: "trash"),
                                 controlType: .Button)
        case .emptyPasteboard:
            return SwitchBarInfo(title: "Empty Pasteboard",
                                 onImage: NSImage(systemSymbolName: "doc.on.clipboard"),
                                 offImage: NSImage(systemSymbolName: "doc.on.clipboard"),
                                 controlType: .Button)
        case .showUserLibrary:
            return SwitchBarInfo(title: "Show User Library",
                                 onImage: NSImage(systemSymbolName: "building.columns.fill"),
                                 offImage: NSImage(systemSymbolName: "building.columns"))
        case .showExtensionName:
            return SwitchBarInfo(title: "Show Extension Name",
                                 onImage: NSImage(named: "extension_on")!,
                                 offImage: NSImage(named: "extension_off")!)
        case .pomodoroTimer:
            return SwitchBarInfo(title: "Pomodoro Timer",
                                 onImage: NSImage(systemSymbolName: "timer"),
                                 offImage: NSImage(systemSymbolName: "timer"))
        case .smallLaunchpadIcon:
            return SwitchBarInfo(title: "Small Launchpad Icon",
                                 onImage: NSImage(systemSymbolName: "square.grid.4x3.fill"),
                                 offImage: NSImage(systemSymbolName: "square.grid.4x3.fill"))
        case .lowpowerMode:
            return SwitchBarInfo(title: "Low Power Mode",
                                 onImage: NSImage(systemSymbolName: "bolt.circle"),
                                 offImage: NSImage(systemSymbolName: "bolt.circle.fill"))
        }
    }
    
    func getNewSwitchInstance() -> SwitchProvider {
        switch self {
        case .hiddeDesktop:
            return HiddenDesktopSwitch()
        case .darkMode:
            return DarkModeSwitch()
        case .topNotch:
            return TopNotchSwitch()
        case .mute:
            return MuteSwitch()
        case .keepAwake:
            return KeepAwakeSwitch()
        case .screenSaver:
            return ScreenSaverSwitch()
        case .nightShift:
            return NightShiftSwitch()
        case .autohideDock:
            return AutohideDockSwitch()
        case .autohideMenuBar:
            return AutohideMenuBarSwitch()
        case .airPods:
            return AirPodsSwitch()
        case .bluetooth:
            return BluetoothSwitch()
        case .xcodeCache:
            return XcodeCacheSwitch()
        case .hiddenFiles:
            return HiddenFilesSwitch()
        case .radioStation:
            return RadioStationSwitch.shared
        case .emptyTrash:
            return EmptyTrashSwitch()
        case .emptyPasteboard:
            return EmptyPasteboardSwitch()
        case .showUserLibrary:
            return ShowUserLibrarySwitch()
        case .showExtensionName:
            return ShowExtensionNameSwitch()
        case .pomodoroTimer:
            return PomodoroTimerSwitch()
        case .smallLaunchpadIcon:
            return SmallLaunchpadIconSwitch()
        case .lowpowerMode:
            return LowPowerModeSwitch()
        }
    }
}

let switchTypeCount = SwitchType.allCases.count

enum ControlType{
    case Switch
    case Button
}
