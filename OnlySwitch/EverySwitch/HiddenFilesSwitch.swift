//
//  HiddenFilesSwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/8.
//

import AppKit
import Switches
import Defines

class HiddenFilesSwitch: SwitchProvider {
    weak var delegate: SwitchDelegate?
    var type: SwitchType = .hiddenFiles
    
    func currentInfo() -> String {
        return ""
    }
    
    func currentStatus() -> Bool {
        do {
            let result = try ShowHiddenFilesCMD.status.runAppleScript(isShellCMD: true)
            return (result as NSString).boolValue
        } catch {
            return false
        }
        
    }
    
    func isVisible() -> Bool {
        return true
    }
    
    func operateSwitch(isOn: Bool) async throws {
        do {
            if isOn {
                _ = try ShowHiddenFilesCMD.on.runAppleScript(isShellCMD: true)
            } else {
                _ = try ShowHiddenFilesCMD.off.runAppleScript(isShellCMD: true)
            }
        } catch {
            throw SwitchError.OperationFailed
        }
        
    }
}
