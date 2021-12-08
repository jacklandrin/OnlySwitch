//
//  AutohideMenuBarSwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/8.
//

import Foundation

class AutohideMenuBarSwitch:SwitchProvider {
    static let shared = AutohideMenuBarSwitch()
    
    func currentStatus() -> Bool {
        let result = getAutoHideMenuBarCMD.runAppleScript()
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
            return setAutohideMenuBarEnableCMD.runAppleScript().0
        } else {
            return setAutohideMenuBarDisableCMD.runAppleScript().0
        }
    }
}
