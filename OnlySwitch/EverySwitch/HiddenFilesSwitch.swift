//
//  HiddenFilesSwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/8.
//

import AppKit

class HiddenFilesSwitch:SwitchProvider {
    var delegate: SwitchDelegate?
    var type: SwitchType = .hiddenFiles
    
    func currentInfo() -> String {
        return ""
    }
    
    func currentStatus() -> Bool {
        let result = ShowHiddenFilesCMD.status.runAppleScript(isShellCMD: true)
        if result.0 {
            return (result.1 as! NSString).boolValue
        }
        return false
    }
    
    func isVisable() -> Bool {
        return true
    }
    
    func operationSwitch(isOn: Bool) async -> Bool {
        if isOn {
            return ShowHiddenFilesCMD.on.runAppleScript(isShellCMD: true).0
        } else {
            return ShowHiddenFilesCMD.off.runAppleScript(isShellCMD: true).0
        }
    }
}
