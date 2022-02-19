//
//  EmptyTrashSwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/16.
//

import Foundation

class EmptyTrashSwitch:SwitchProvider {
    
    var type: SwitchType = .emptyTrash
    var delegate: SwitchDelegate?
    func currentInfo() -> String {
        return ""
    }
    
    func currentStatus() -> Bool {
        return false
    }
    
    func operationSwitch(isOn: Bool) async -> Bool {
        if isOn {
            return emptyTrashCMD.runAppleScript().0
        }
        return true
    }
    
    func isVisable() -> Bool {
        return true
    }
}
