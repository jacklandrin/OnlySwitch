//
//  LowPowerModeSwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/1/1.
//

import Foundation

class LowPowerModeSwitch:SwitchProvider {
    var type: SwitchType = .lowpowerMode
    
    var switchBarVM: SwitchBarVM = SwitchBarVM(switchType: .lowpowerMode)
    
    init() {
        self.switchBarVM.switchOperator = self
    }
    
    func currentStatus() -> Bool {
        let result = getLowpowerModeCMD.runAppleScript(isShellCMD: true)
        let content = result.1 as! String
        return content.contains("1")
    }
    
    func currentInfo() -> String {
        return ""
    }
    
    func operationSwitch(isOn: Bool) async -> Bool {
        if isOn {
            return setLowpowerModeCMD.runAppleScript(isShellCMD: true, with: true).0
        } else {
            return unsetLowpowerModeCMD.runAppleScript(isShellCMD: true, with: true).0
        }
    }
    
    func isVisable() -> Bool {
        return true
    }
    
    
}
