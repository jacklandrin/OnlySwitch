//
//  HiddenDesktopSwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/11/30.
//

import AppKit

class HiddenDesktopSwitch:SwitchProvider {
    weak var delegate: SwitchDelegate?
    
    var type: SwitchType = .hiddeDesktop
    
    func currentStatus() -> Bool {
        do {
            let result = try HideDesktopCMD.status.runAppleScript(isShellCMD: true)
            
            if result == "0" {
                return true
            } else {
                return false
            }
        } catch {
            return false
        }
    }
    
    func operateSwitch(isOn: Bool) async throws {
        do {
            if isOn {
               _ = try HideDesktopCMD.on.runAppleScript(isShellCMD: true)
            } else {
               _ = try HideDesktopCMD.off.runAppleScript(isShellCMD: true)
            }
        } catch {
            throw SwitchError.OperationFailed
        }
    }
    
    func isVisible() -> Bool {
        return true
    }
    
    func currentInfo() -> String {
        return ""
    }
    
    deinit{
        print("hidden desktop switch deinit")
    }
}
