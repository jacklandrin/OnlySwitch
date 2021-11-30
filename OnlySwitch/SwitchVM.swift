//
//  SwitchVM.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/11/29.
//

import SwiftUI

//let notchHeight:CGFloat = 76.0

enum SwitchType {
    case hiddeDesktop, darkMode, topNotch
    
    func switchTitle() -> (String, NSImage) {
        switch self {
        case .hiddeDesktop:
            return ("Hide Desktop", NSImage(systemSymbolName: "desktopcomputer", accessibilityDescription: nil)!)
        case .darkMode:
            return ("Dark Mode", NSImage(systemSymbolName: "circle.circle.fill", accessibilityDescription: nil)!)
        case .topNotch:
            return ("Hide Notch", NSImage(systemSymbolName: "laptopcomputer", accessibilityDescription: nil)!)
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
        }
    }
    
}

class SwitchOptionVM : ObservableObject, Identifiable {
    @Published var switchType:SwitchType
    var _isOn:Bool
    var isOn:Bool
    {
        set {
            let success = switchType.turnSwitch(isOn: newValue)
            if success {
                _isOn = newValue
                objectWillChange.send()
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
    }
    
}

class SwitchVM : ObservableObject {
    @Published var switchList:[SwitchOptionVM] = [SwitchOptionVM(switchType: .hiddeDesktop),
                                                  SwitchOptionVM(switchType: .darkMode),
                                                  SwitchOptionVM(switchType: .topNotch)]
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
