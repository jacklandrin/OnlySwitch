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
    case hiddeDesktop, darkMode, topNotch, mute
    
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
        }
    }
    
    func turnSwitch(isOn:Bool) async -> Bool {
        switch self {
        case .hiddeDesktop:
            return HiddenDesktopSwitch.shared.operationSwitch(isOn: isOn)
        case .darkMode:
            return DarkModeSwitch.shared.operationSwitch(isOn: isOn)
        case .topNotch:
            return TopNotchSwitch.shared.operationSwitch(isOn: isOn)
        case .mute:
            return MuteSwitch.shared.operationSwitch(isOn: isOn)
        }
    }
    
    
    func isOnInitailValue() -> Bool {
        switch self {
        case .hiddeDesktop:
            return HiddenDesktopSwitch.shared.currentStatus()
        case .darkMode:
            return DarkModeSwitch.shared.currentStatus()
        case .topNotch:
            return TopNotchSwitch.shared.currentStatus()
        case .mute:
            return MuteSwitch.shared.currentStatus()
        }
    }
    
    func isVisible() -> Bool {
        switch self {
        case .hiddeDesktop:
            return true
        case .darkMode:
            return true
        case .topNotch:
            return TopNotchSwitch.shared.isNotchScreen
        case .mute:
            return true
        }
    }
    
}
