//
//  ShowExtensionNameSwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/21.
//

import Foundation
import Switches
import Defines

class ShowExtensionNameSwitch: SwitchProvider {
    var type: SwitchType = .showExtensionName
    weak var delegate: SwitchDelegate?
    
    func currentStatus() -> Bool {
        do {
            let result = try ShowExtensionNameCMD.status.runAppleScript(isShellCMD: true)
           
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
                _ = try ShowExtensionNameCMD.on.runAppleScript(isShellCMD: true)
            } else {
                _ = try ShowExtensionNameCMD.off.runAppleScript(isShellCMD: true)
            }
        } catch {
            throw SwitchError.OperationFailed
        }
        
    }
    
    func isVisible() -> Bool {
        return true
    }

}
