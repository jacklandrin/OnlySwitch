//
//  AutohideDockSwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/6.
//

import AppKit

class AutohideDockSwitch:SwitchProvider {

    var type: SwitchType = .autohideDock

    func currentStatus() -> Bool {
        let result = getAutohideDockCMD.runAppleScript()
        if result.0 {
            return (result.1 as! NSString).boolValue
        }
        return false
    }
    
    func currentInfo() -> String {
        return ""
    }
    
    
    func isVisable() -> Bool {
        return true
    }
    
    func operationSwitch(isOn: Bool) async -> Bool {
        if isOn {
            return setAutohideDockEnableCMD.runAppleScript().0
        } else {
            return setAutohideDockDisableCMD.runAppleScript().0
        }
    }
}
