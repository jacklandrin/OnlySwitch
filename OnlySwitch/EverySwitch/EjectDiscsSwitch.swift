//
//  EjectDiscsSwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/11/24.
//

import Foundation

class EjectDiscsSWitch: SwitchProvider {
    var type: SwitchType = .ejectDiscs
    
    var delegate: SwitchDelegate?
    
    func currentStatus() -> Bool {
        return true
    }
    
    func currentInfo() -> String {
        return ""
    }
    
    func operationSwitch(isOn: Bool) async throws {
        if isOn {
            _ = try ejectDiscs.runAppleScript()
        }
    }
    
    func isVisable() -> Bool {
        return true
    }
    
    
}
