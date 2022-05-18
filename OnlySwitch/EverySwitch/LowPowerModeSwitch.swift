//
//  LowPowerModeSwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/1/1.
//

import Foundation

class LowPowerModeSwitch:SwitchProvider {
    var type: SwitchType = .lowpowerMode
    weak var delegate: SwitchDelegate?
    func currentStatus() -> Bool {
        do {
            let result = try LowpowerModeCMD.status.runAppleScript(isShellCMD: true)
            return result.contains("1")
        } catch {
            return false
        }
    }
    
    func currentInfo() -> String {
        return "require password"
    }
    
    func operationSwitch(isOn: Bool) async throws {
        do {
            if isOn {
                _ = try LowpowerModeCMD.on.runAppleScript(isShellCMD: true, with: true)
            } else {
                _ = try LowpowerModeCMD.off.runAppleScript(isShellCMD: true, with: true)
            }
        } catch {
            throw SwitchError.OperationFailed
        }
        
    }
    
    func isVisable() -> Bool {
        return true
    }
    
    
}
