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

enum SwitchType:UInt64 {
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
            return RadioStationSwitch()
        }
    }
}

let switchTypeCount = 14

enum ControlType{
    case Switch
    case Button
}
