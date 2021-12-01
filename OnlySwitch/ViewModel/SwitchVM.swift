//
//  SwitchVM.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/11/29.
//

import SwiftUI

struct SwitchBar {
    let title:String
    let onImage:NSImage
    let offImage:NSImage
}

enum SwitchType {
    case hiddeDesktop, darkMode, topNotch, mute
    
    func switchTitle() -> SwitchBar {
        switch self {
        case .hiddeDesktop:
            return SwitchBar(title:"Hide Desktop", onImage:NSImage(named: "desktopcomputer")!, offImage:NSImage(named: "desktop_with_icon")!)
        case .darkMode:
            return SwitchBar(title:"Dark Mode", onImage:NSImage(named: "darkmode_on")!, offImage: NSImage(named: "darkmode_off")!)
        case .topNotch:
            return SwitchBar(title:"Hide Notch", onImage:NSImage(named:"laptopnotchhidden")!, offImage: NSImage(named: "laptopwithnotch")!)
        case .mute:
            return SwitchBar(title: "Mute", onImage: NSImage(systemSymbolName: "speaker.slash.circle"), offImage: NSImage(systemSymbolName: "speaker.wave.2.circle"))
        }
    }
    
    func turnSwitch(isOn:Bool) -> Bool {
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

class SwitchOptionVM : ObservableObject, Identifiable {
    @Published var switchType:SwitchType
    @Published var isHidden  = false
    private var _isOn:Bool
    var isOn:Bool
    {
        set {
            let success = switchType.turnSwitch(isOn: newValue)
            if success {
                withAnimation(.spring()) {
                    _isOn = newValue
                    objectWillChange.send()
                }
            }
        }
        
        get{
            return _isOn
        }
    }
    
    init(switchType:SwitchType) {
        self.switchType = switchType
        _isOn = false
    }
    
    func refreshStatus() {
        _isOn = self.switchType.isOnInitailValue()
        isHidden = !self.switchType.isVisible()
    }
    
}

class SwitchVM : ObservableObject {
    @Published var switchList:[SwitchOptionVM] = [SwitchOptionVM(switchType: .hiddeDesktop),
                                                  SwitchOptionVM(switchType: .darkMode),
                                                  SwitchOptionVM(switchType: .topNotch),
                                                  SwitchOptionVM(switchType: .mute)]
    @Published var startatLogin = false
    
    func refreshSwitchStatus() {
        for option in switchList {
            option.refreshStatus()
        }
    }
    
//    @discardableResult
//    func runShell(_ command: String) -> Int32 {
//        let task = Process()
//        task.launchPath = "/bin/zsh"
//        task.arguments = ["-c", command]
//        task.launch()
//        task.waitUntilExit()
//        return task.terminationStatus
//    }

        
}
