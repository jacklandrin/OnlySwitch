//
//  LowPowerModeSwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/1/1.
//

import Foundation

class LowPowerModeSwitch:SwitchProvider {
    var type: SwitchType = .lowpowerMode
    var delegate: SwitchDelegate?
    func currentStatus() -> Bool {
        let result = LowpowerModeCMD.status.runAppleScript(isShellCMD: true)
        let content = result.1 as! String
        return content.contains("1")
    }
    
    func currentInfo() -> String {
        return "require password"
    }
    
    func operationSwitch(isOn: Bool) async -> Bool {
        if isOn {
            return LowpowerModeCMD.on.runAppleScript(isShellCMD: true, with: true).0
        } else {
            return LowpowerModeCMD.off.runAppleScript(isShellCMD: true, with: true).0
        }
    }
    
    func isVisable() -> Bool {
        return true
    }
    
    
}
