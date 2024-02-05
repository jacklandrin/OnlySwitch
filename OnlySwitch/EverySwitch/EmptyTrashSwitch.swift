//
//  EmptyTrashSwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/16.
//

import Foundation
import Switches
import Defines

class EmptyTrashSwitch:SwitchProvider {
    
    var type: SwitchType = .emptyTrash
    weak var delegate: SwitchDelegate?
    func currentInfo() -> String {
        return ""
    }
    
    func currentStatus() -> Bool {
        return true
    }
    
    func operateSwitch(isOn: Bool) async throws {
        do {
            if isOn {
                _ = try emptyTrashCMD.runAppleScript()
            }
        } catch {
            throw SwitchError.OperationFailed
        }
        
    }
    
    func isVisible() -> Bool {
        return true
    }
}
