//
//  EjectDiscsSwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/11/24.
//

import Foundation
import Switches

class EjectDiscsSWitch: SwitchProvider {
    var type: SwitchType = .ejectDiscs
    
    var delegate: SwitchDelegate?
    
    func currentStatus() -> Bool {
        return true
    }
    
    func currentInfo() -> String {
        return ""
    }
    
    func operateSwitch(isOn: Bool) async throws {
        if isOn {
            _ = try ejectDiscs.runAppleScript()
        }
    }
    
    func isVisible() -> Bool {
        return true
    }
    
    
}
