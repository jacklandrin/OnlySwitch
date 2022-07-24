//
//  AppleMusicSwitch.swift
//  OnlySwitchTests
//
//  Created by Jacklandrin on 2022/7/24.
//

import Foundation
class AppleMusicSwitch:SwitchProvider {
    var type: SwitchType = .applemusic
    
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
    
    static let shared = AppleMusicSwitch()
    
}
