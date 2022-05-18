//
//  DockRecentSwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/1/21.
//

import Foundation

class DockRecentSwitch:SwitchProvider {
    var type: SwitchType = .dockRecent
    weak var delegate: SwitchDelegate?
    func currentStatus() -> Bool {
        do {
            let result = try ShowDockRecentCMD.status.runAppleScript(isShellCMD: true)
            return (result as NSString).boolValue
        } catch {
            return false
        }
        
    }
    
    func currentInfo() -> String {
        return ""
    }
    
    func operationSwitch(isOn: Bool) async throws {
        do {
            if isOn {
                _ = try ShowDockRecentCMD.on.runAppleScript(isShellCMD: true)
            } else {
                _ = try ShowDockRecentCMD.off.runAppleScript(isShellCMD: true)
            }
        } catch {
            throw SwitchError.OperationFailed
        }
        
    }
    
    func isVisable() -> Bool {
        return true
    }
    
    
}
