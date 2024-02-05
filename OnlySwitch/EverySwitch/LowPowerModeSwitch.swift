//
//  LowPowerModeSwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/1/1.
//

import Foundation
import Switches
import Defines

class LowPowerModeSwitch: SwitchProvider {
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
    
    func operateSwitch(isOn: Bool) async throws {
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
    
    func isVisible() -> Bool {
        return true
    }
}
