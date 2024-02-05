//
//  AutohideMenuBarSwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/8.
//

import AppKit
import Switches
import Defines

class AutohideMenuBarSwitch: SwitchProvider {
    weak var delegate: SwitchDelegate?
    var type: SwitchType = .autohideMenuBar
    
    func currentStatus() -> Bool {
        do {
            let result = try AutoHideMenuBarCMD.status.runAppleScript()
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
                _ = try AutoHideMenuBarCMD.on.runAppleScript()
            } else {
                _ = try AutoHideMenuBarCMD.off.runAppleScript()
            }
        } catch {
            throw SwitchError.OperationFailed
        }
        
    }
}
