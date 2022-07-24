//
//  SpotifySwitch.swift
//  OnlySwitchTests
//
//  Created by Jacklandrin on 2022/7/24.
//

import Foundation
class SpotifySwitch: SwitchProvider {
    var type: SwitchType = .spotify
    
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
    
    static let shared = SpotifySwitch()
    
}
