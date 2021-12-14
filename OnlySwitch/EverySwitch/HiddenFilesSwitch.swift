//
//  HiddenFilesSwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/8.
//

import AppKit

class HiddenFilesSwitch:SwitchProvider {
//    static let shared = HiddenFilesSwitch()
    var type: SwitchType = .hiddenFiles
    var switchBarVM: SwitchBarVM = SwitchBarVM(switchType: .hiddenFiles)
    var barInfo: SwitchBarInfo = SwitchBarInfo(title: "Show Hidden Files".localized(),
                                               onImage: NSImage(systemSymbolName: "eye"),
                                               offImage: NSImage(systemSymbolName: "eye.slash"))
    init() {
        switchBarVM.switchOperator = self
    }
    
    func currentInfo() -> String {
        return ""
    }
    
    func currentStatus() -> Bool {
        let result = getHiddenFilesStateCMD.runAppleScript(isShellCMD: true)
        if result.0 {
            return (result.1 as! NSString).boolValue
        }
        return false
    }
    
    func isVisable() -> Bool {
        return true
    }
    
    func operationSwitch(isOn: Bool) async -> Bool {
        if isOn {
            return setHiddenFilesShowCMD.runAppleScript(isShellCMD: true).0
        } else {
            return setHiddenFilesHideCMD.runAppleScript(isShellCMD: true).0
        }
    }
}
