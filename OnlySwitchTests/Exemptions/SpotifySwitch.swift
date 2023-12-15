//
//  SpotifySwitch.swift
//  OnlySwitchTests
//
//  Created by Jacklandrin on 2022/7/24.
//

import Foundation
@testable import OnlySwitch

class SpotifySwitch: SwitchProvider {    
    var type: SwitchType = .spotify
    
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
    
    static let shared = SpotifySwitch()
    
}
