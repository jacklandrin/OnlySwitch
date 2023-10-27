//
//  TrueToneSwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2023/10/27.
//

import Foundation

class TrueToneSwitch: SwitchProvider {
    var type: SwitchType = .trueTone
    
    var delegate: SwitchDelegate?
    
    func currentStatus() -> Bool {
        CBTrueToneClient.shared.isTrueToneEnabled
    }
    
    func currentInfo() -> String {
        ""
    }
    
    func operateSwitch(isOn: Bool) async throws {
        CBTrueToneClient.shared.isTrueToneEnabled = isOn
    }
    
    func isVisible() -> Bool {
        CBTrueToneClient.shared.isTrueToneSupported && CBTrueToneClient.shared.isTrueToneAvailable
    }
    

}
