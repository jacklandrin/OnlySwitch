//
//  HiddenDesktopSwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/11/30.
//

import AppKit

class HiddenDesktopSwitch:SwitchProvider {
    
    var type: SwitchType = .hiddeDesktop
    var switchBarVM: SwitchBarVM = SwitchBarVM(switchType: .hiddeDesktop)
    
    init() {
        switchBarVM.switchOperator = self
    }
    
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
    
    func operationSwitch(isOn: Bool) async -> Bool {
        if isOn {
            return hideDesktopCMD.runAppleScript(isShellCMD: true).0
        } else {
            return showDesktopCMD.runAppleScript(isShellCMD: true).0
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
