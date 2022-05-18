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
    
    func operationSwitch(isOn: Bool) async throws {
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
    
    func isVisable() -> Bool {
        return true
    }
    
    func currentInfo() -> String {
        return ""
    }
}
