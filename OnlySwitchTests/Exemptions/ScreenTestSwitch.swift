//
//  ScreenTestSwitch.swift
//  OnlySwitchTests
//
//  Created by Jacklandrin on 2022/7/24.
//

import Foundation
@testable import OnlySwitch

class ScreenTestSwitch:SwitchProvider {
    var type: SwitchType = .screenTest
    
    var delegate: SwitchDelegate?
    
    func currentStatus() -> Bool {
        return false
    }
    
    func currentInfo() -> String {
        return ""
    }
    
    func operateSwitch(isOn: Bool) async throws {
        
    }
    
    func isVisible() -> Bool {
        return false
    }
    
    static let shared = ScreenTestSwitch()
    
}
