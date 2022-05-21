//
//  EmptyTrashSwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/16.
//

import Foundation

class EmptyTrashSwitch:SwitchProvider {
    
    var type: SwitchType = .emptyTrash
    weak var delegate: SwitchDelegate?
    func currentInfo() -> String {
        return ""
    }
    
    func currentStatus() -> Bool {
        return true
    }
    
    func operationSwitch(isOn: Bool) async throws {
        do {
            if isOn {
                _ = try emptyTrashCMD.runAppleScript()
            }
        } catch {
            throw SwitchError.OperationFailed
        }
        
    }
    
    func isVisable() -> Bool {
        return true
    }
}
