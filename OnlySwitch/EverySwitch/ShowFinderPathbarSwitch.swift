//
//  ShowFinderPathbarSwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/1/13.
//

import Foundation

class ShowFinderPathbarSwitch:SwitchProvider {
    var type: SwitchType = .showFinderPathbar
    
    func currentStatus() -> Bool {
        let result = ShowPathBarCMD.status.runAppleScript(isShellCMD: true)
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
            return ShowPathBarCMD.on.runAppleScript(isShellCMD: true).0
        } else {
            return ShowPathBarCMD.off.runAppleScript(isShellCMD: true).0
        }
    }
    
    func isVisable() -> Bool {
        return true
    }
    
    
}
