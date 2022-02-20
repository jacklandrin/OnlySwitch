//
//  DarkModeSwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/11/30.
//

import AppKit

class DarkModeSwitch:SwitchProvider {
    weak var delegate: SwitchDelegate?
    var type: SwitchType = .darkMode
    
    func currentStatus() -> Bool {
        let result = DarkModeCMD.status.runAppleScript(isShellCMD: true)
        if result.0 {
            if (result.1 as! String) == "Dark" {
                return true
            } else {
                return false
            }
        }
        return false
    }
    
    func operationSwitch(isOn: Bool) async -> Bool {
        if isOn {
            return DarkModeCMD.on.runAppleScript().0
        } else {
            return DarkModeCMD.off.runAppleScript().0
        }
    }
    
    func isVisable() -> Bool {
        return true
    }
    
    func currentInfo() -> String {
        return ""
    }
}
