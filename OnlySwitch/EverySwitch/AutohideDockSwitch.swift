//
//  AutohideDockSwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/6.
//

import AppKit

class AutohideDockSwitch:SwitchProvider {
    weak var delegate: SwitchDelegate?
    var type: SwitchType = .autohideDock

    func currentStatus() -> Bool {
        do {
            let result = try AutohideDockCMD.status.runAppleScript()
            return (result as NSString).boolValue
            
        } catch {
            return false
        }
    }
    
    func currentInfo() -> String {
        return ""
    }
    
    
    func isVisible() -> Bool {
        return true
    }
    
    func operateSwitch(isOn: Bool) async throws {
        do {
            if isOn {
                _ = try AutohideDockCMD.on.runAppleScript()
            } else {
                _ = try AutohideDockCMD.off.runAppleScript()
            }
        } catch {
            throw SwitchError.OperationFailed
        }
    }
}
