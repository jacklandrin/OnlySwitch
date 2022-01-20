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
        let result = getPathbarStatusCMD.runAppleScript(isShellCMD: true)
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
            return showPathbarCMD.runAppleScript(isShellCMD: true).0
        } else {
            return hidePathbarCMD.runAppleScript(isShellCMD: true).0
        }
    }
    
    func isVisable() -> Bool {
        return true
    }
    
    
}
