//
//  TrueToneSwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2023/10/27.
//

import Foundation
import Switches

final class TrueToneSwitch: SwitchProvider {
    var type: SwitchType = .trueTone
    
    var delegate: SwitchDelegate?

    @MainActor
    func currentStatus() async -> Bool {
        CBTrueToneClient.shared.isTrueToneEnabled
    }

    @MainActor
    func currentInfo() async -> String {
        ""
    }

    @MainActor
    func operateSwitch(isOn: Bool) async throws {
        CBTrueToneClient.shared.isTrueToneEnabled = isOn
    }
    
    func isVisible() -> Bool {
        CBTrueToneClient.shared.isTrueToneSupported && CBTrueToneClient.shared.isTrueToneAvailable
    }
}
