//
//  HiddenDesktopSwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/11/30.
//

import AppKit

class HiddenDesktopSwitch:SwitchProvider {
    weak var delegate: SwitchDelegate?
    
    var type: SwitchType = .hiddeDesktop
    
    func currentStatus() -> Bool {
        let result = HideDesktopCMD.status.runAppleScript(isShellCMD: true)
        if result.0 {
            if (result.1 as! String) == "0" {
                return true
            } else {
                return false
            }
        }
        return false
    }
    
    func operationSwitch(isOn: Bool) async -> Bool {
        if isOn {
            return HideDesktopCMD.on.runAppleScript(isShellCMD: true).0
        } else {
            return HideDesktopCMD.off.runAppleScript(isShellCMD: true).0
        }
    }
    
    func isVisable() -> Bool {
        return true
    }
    
    func currentInfo() -> String {
        return ""
    }
    
    deinit{
        print("hidden desktop switch deinit")
    }
}
