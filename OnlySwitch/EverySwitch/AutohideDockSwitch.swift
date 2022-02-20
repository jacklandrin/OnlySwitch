//
//  AutohideDockSwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/6.
//

import AppKit

class AutohideDockSwitch:SwitchProvider {
    weak var delegate: SwitchDelegate?
    var type: SwitchType = .autohideDock

    func currentStatus() -> Bool {
        let result = AutohideDockCMD.status.runAppleScript()
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
            return AutohideDockCMD.on.runAppleScript().0
        } else {
            return AutohideDockCMD.off.runAppleScript().0
        }
    }
}
