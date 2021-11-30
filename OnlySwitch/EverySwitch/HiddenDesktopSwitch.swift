//
//  HiddenDesktopSwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/11/30.
//

import Foundation

class HiddenDesktopSwitch:SwitchProtocal {
    static let shared = HiddenDesktopSwitch()
    func currentStatus() -> Bool {
        let result = currentDesktopStatusCMD.runAppleScript(isShellCMD: true)
        if result.0 {
            if (result.1 as! String) == "0" {
                return true
            } else {
                return false
            }
        }
        return false
    }
    
    func operationSwitch(isOn: Bool) -> Bool {
        if isOn {
            return hiddleDesktopCMD.runAppleScript(isShellCMD: true).0
        } else {
            return showDesktopCMD.runAppleScript(isShellCMD: true).0
        }
    }
}
