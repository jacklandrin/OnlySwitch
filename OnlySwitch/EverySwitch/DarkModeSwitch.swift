//
//  DarkModeSwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/11/30.
//

import Foundation

class DarkModeSwitch:SwitchProtocal {
    static let shared = DarkModeSwitch()
    func currentStatus() -> Bool {
        let result = currentInferfaceStyle.runAppleScript(isShellCMD: true)
        if result.0 {
            if (result.1 as! String) == "Dark" {
                return true
            } else {
                return false
            }
        }
        return false
    }
    
    func operationSwitch(isOn: Bool) -> Bool {
        if isOn {
            return turnOnDarkModeCMD.runAppleScript().0
        } else {
            return turnOffDarkModeCMD.runAppleScript().0
        }
    }
}
