//
//  ScreenTestSwitch.swift
//  OnlySwitchTests
//
//  Created by Jacklandrin on 2022/7/24.
//

import Foundation
class ScreenTestSwitch:SwitchProvider {
    var type: SwitchType = .screenTest
    
    var delegate: SwitchDelegate?
    
    func currentStatus() -> Bool {
        return false
    }
    
    func currentInfo() -> String {
        return ""
    }
    
    func operationSwitch(isOn: Bool) async throws {
        
    }
    
    func isVisable() -> Bool {
        return false
    }
    
    static let shared = ScreenTestSwitch()
    
}
