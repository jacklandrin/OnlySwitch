//
//  EjectDiscsSwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/11/24.
//

import Foundation
import Switches

final class EjectDiscsSWitch: SwitchProvider {
    var type: SwitchType = .ejectDiscs
    
    var delegate: SwitchDelegate?

    @MainActor
    func currentStatus() async -> Bool {
        return true
    }

    @MainActor
    func currentInfo() async -> String {
        return ""
    }

    @MainActor
    func operateSwitch(isOn: Bool) async throws {
        if isOn {
            _ = try await ejectDiscs.runAppleScript()
        }
    }
    
    func isVisible() -> Bool {
        return true
    }
    
    
}
