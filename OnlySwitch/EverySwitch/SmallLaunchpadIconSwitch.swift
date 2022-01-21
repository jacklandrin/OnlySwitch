//
//  SmallLaunchpadIconSwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/26.
//

import Foundation

class SmallLaunchpadIconSwitch:SwitchProvider {
    var type: SwitchType = .smallLaunchpadIcon
    
    func currentStatus() -> Bool {
        let result = SmallLaunchpadCMD.status.runAppleScript(isShellCMD: true)
        if result.0 {
            if (result.1 as! NSString).intValue > 5 {
                return true
            }
        }
        return false
    }
    
    func currentInfo() -> String {
        return ""
    }
    
    func operationSwitch(isOn: Bool) async -> Bool {
        if isOn {
            return SmallLaunchpadCMD.on.runAppleScript(isShellCMD: true).0
        } else {
            return SmallLaunchpadCMD.off.runAppleScript(isShellCMD: true).0
        }
    }
    
    func isVisable() -> Bool {
        return true
    }
    
    
}
