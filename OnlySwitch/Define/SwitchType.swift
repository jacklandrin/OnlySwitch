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
        }
    }
    
}
