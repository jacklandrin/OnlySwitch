//
//  RadioStationSwitch.swift
//  OnlySwitchTests
//
//  Created by Jacklandrin on 2022/7/24.
//

import Foundation
class RadioStationSwitch:SwitchProvider {
    static let shared = RadioStationSwitch()
    var type: SwitchType = .radioStation
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
    
    
}
