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
}

enum SwitchType {
    case hiddeDesktop, darkMode, topNotch, mute, screenSaver, nightShift, autohideDock, airPods, bluetooth, xcodeCache, autohideMenuBar, hiddenFiles
    
    func switchTitle() -> SwitchBarInfo {
        switch self {
        case .hiddeDesktop:
            return SwitchBarInfo(title:"Hide Desktop", onImage:NSImage(named: "desktopcomputer")!, offImage:NSImage(named: "desktop_with_icon")!)
        case .darkMode:
            return SwitchBarInfo(title:"Dark Mode", onImage:NSImage(named: "darkmode_on")!, offImage: NSImage(named: "darkmode_off")!)
        case .topNotch:
            return SwitchBarInfo(title:"Hide Notch", onImage:NSImage(named:"laptopnotchhidden")!, offImage: NSImage(named: "laptopwithnotch")!)
        case .mute:
            return SwitchBarInfo(title: "Mute", onImage: NSImage(systemSymbolName: "speaker.slash.circle"), offImage: NSImage(systemSymbolName: "speaker.wave.2.circle"))
        case .screenSaver:
            return SwitchBarInfo(title: "Screen Saver", onImage: NSImage(systemSymbolName: "display"), offImage: NSImage(systemSymbolName: "display"))
        case .nightShift:
            return SwitchBarInfo(title: "Night Shift", onImage: NSImage(systemSymbolName: "moon.stars.fill"), offImage: NSImage(systemSymbolName: "moon.stars"))
        case .autohideDock:
            return SwitchBarInfo(title: "Autohide Dock", onImage: NSImage(systemSymbolName: "dock.arrow.down.rectangle"), offImage: NSImage(systemSymbolName: "dock.rectangle"))
        case .airPods:
            return SwitchBarInfo(title: "AirPods", onImage: NSImage(systemSymbolName: "airpodspro"), offImage: NSImage(systemSymbolName: "airpodspro"))
        case .bluetooth:
            return SwitchBarInfo(title: "Bluetooth", onImage: NSImage(named: "bluetooth_on")!, offImage: NSImage(named: "bluetooth_off")!)
        case .xcodeCache:
            return SwitchBarInfo(title: "Xcode Derived Data", onImage: NSImage(systemSymbolName: "hammer.circle.fill"), offImage: NSImage(systemSymbolName: "hammer.circle"))
        case .autohideMenuBar:
            return SwitchBarInfo(title: "Autohide Menu Bar", onImage: NSImage(systemSymbolName: "menubar.arrow.up.rectangle"), offImage: NSImage(systemSymbolName: "menubar.rectangle"))
        case .hiddenFiles:
            return SwitchBarInfo(title: "Show Hidden Files", onImage: NSImage(systemSymbolName: "eye"), offImage: NSImage(systemSymbolName: "eye.slash"))
        }
    }

    func switchOperator() -> SwitchProvider {
        switch self {
        case .hiddeDesktop:
            return HiddenDesktopSwitch.shared
        case .darkMode:
            return DarkModeSwitch.shared
        case .topNotch:
            return TopNotchSwitch.shared
        case .mute:
            return MuteSwitch.shared
        case .screenSaver:
            return ScreenSaverSwitch.shared
        case .nightShift:
            return NightShiftSwitch.shared
        case .autohideDock:
            return AutohideDockSwitch.shared
        case .airPods:
            return AirPodsSwitch.shared
        case .bluetooth:
            return BluetoothSwitch.shared
        case .xcodeCache:
            return XcodeCacheSwitch.shared
        case .autohideMenuBar:
            return AutohideMenuBarSwitch.shared
        case .hiddenFiles:
            return HiddenFilesSwitch.shared
        }
    }
    
}
