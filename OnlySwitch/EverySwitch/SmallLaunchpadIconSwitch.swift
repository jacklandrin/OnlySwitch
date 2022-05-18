//
//  SmallLaunchpadIconSwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/26.
//

import Foundation

class SmallLaunchpadIconSwitch:SwitchProvider {
    var type: SwitchType = .smallLaunchpadIcon
    weak var delegate: SwitchDelegate?
    func currentStatus() -> Bool {
        do {
            let result = try SmallLaunchpadCMD.status.runAppleScript(isShellCMD: true)
            
            if (result as NSString).intValue > 5 {
                return true
            }
            return false
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
                _ = try SmallLaunchpadCMD.on.runAppleScript(isShellCMD: true)
            } else {
                _ = try SmallLaunchpadCMD.off.runAppleScript(isShellCMD: true)
            }
        } catch {
            throw SwitchError.OperationFailed
        }
        
    }
    
    func isVisable() -> Bool {
        return true
    }
    
    
}
