//
//  DarkModeSwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/11/30.
//

import AppKit

class DarkModeSwitch:SwitchProvider {
    weak var delegate: SwitchDelegate?
    var type: SwitchType = .darkMode
    
    func currentStatus() -> Bool {
        if #available(macOS 14.0, *) {
            do {
                let result = try DarkModeCMD.status_applescript.runAppleScript()
                return result == "true" ? true : false
            } catch {
                return false
            }
        } else {
            do {
                let result = try DarkModeCMD.status.runAppleScript(isShellCMD: true)

                if result == "Dark" {
                    return true
                } else {
                    return false
                }

            } catch {
                return false
            }
        }
    }
    
    func operateSwitch(isOn: Bool) async throws {
        do {
            if isOn {
                _ = try DarkModeCMD.on.runAppleScript()
            } else {
                _ = try DarkModeCMD.off.runAppleScript()
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
}
