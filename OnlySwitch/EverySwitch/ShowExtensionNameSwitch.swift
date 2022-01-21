//
//  ShowExtensionNameSwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/21.
//

import Foundation

class ShowExtensionNameSwitch:SwitchProvider {
    var type: SwitchType = .showExtensionName
    
    func currentStatus() -> Bool {
        let result = ShowExtensionNameCMD.status.runAppleScript(isShellCMD: true)
        if result.0 {
            return (result.1 as! NSString).boolValue
        }
        return false
    }
    
    func currentInfo() -> String {
        return ""
    }
    
    func operationSwitch(isOn: Bool) async -> Bool {
        if isOn {
            return ShowExtensionNameCMD.on.runAppleScript(isShellCMD: true).0
        } else {
            return ShowExtensionNameCMD.off.runAppleScript(isShellCMD: true).0
        }
    }
    
    func isVisable() -> Bool {
        return true
    }

}
