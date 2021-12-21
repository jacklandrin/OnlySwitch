//
//  ShowExtensionNameSwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/21.
//

import Foundation

class ShowExtensionNameSwitch:SwitchProvider {
    
    init() {
        self.switchBarVM.switchOperator = self
    }
    
    func currentStatus() -> Bool {
        let result = getExtensionNameStateCMD.runAppleScript(isShellCMD: true)
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
            return showExtensionNameCMD.runAppleScript(isShellCMD: true).0
        } else {
            return hideExtensionNameCMD.runAppleScript(isShellCMD: true).0
        }
    }
    
    func isVisable() -> Bool {
        return true
    }
    
    var type: SwitchType = .showExtensionName
    
    var switchBarVM: SwitchBarVM = SwitchBarVM(switchType: .showExtensionName)
    
    
}
