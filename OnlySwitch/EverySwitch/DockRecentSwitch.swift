//
//  DockRecentSwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/1/21.
//

import Foundation

class DockRecentSwitch:SwitchProvider {
    var type: SwitchType = .dockRecent
    
    func currentStatus() -> Bool {
        let result = DockRecentCMD.read.runAppleScript(isShellCMD: true)
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
            return DockRecentCMD.show.runAppleScript(isShellCMD: true).0
        } else {
            return DockRecentCMD.hide.runAppleScript(isShellCMD: true).0
        }
    }
    
    func isVisable() -> Bool {
        return true
    }
    
    
}
