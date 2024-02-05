//
//  ShowFinderPathbarSwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/1/13.
//

import Foundation
import Switches
import Defines

class ShowFinderPathbarSwitch: SwitchProvider {
    var type: SwitchType = .showFinderPathbar
    weak var delegate: SwitchDelegate?
    func currentStatus() -> Bool {
        do {
            let result = try ShowPathBarCMD.status.runAppleScript(isShellCMD: true)
            return (result as NSString).boolValue
        } catch {
            return false
        }
    }
    
    func currentInfo() -> String {
        return ""
    }
    
    func operateSwitch(isOn: Bool) async throws {
        do {
            if isOn {
                _ = try ShowPathBarCMD.on.runAppleScript(isShellCMD: true)
            } else {
                _ = try ShowPathBarCMD.off.runAppleScript(isShellCMD: true)
            }
        } catch {
            throw SwitchError.OperationFailed
        }
    }
    
    func isVisible() -> Bool {
        return true
    }
    
    
}
