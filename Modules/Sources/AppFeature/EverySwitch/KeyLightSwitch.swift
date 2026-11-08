//
//  KeyLightSwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2024/4/2.
//

import Foundation
import Switches
import OnlySwitchObjC

final class KeyLightSwitch: SwitchProvider, @unchecked Sendable {
    static let shared = KeyLightSwitch()
    var type: SwitchType = .keyLight
    var delegate: SwitchDelegate?

    init() {
        KeyboardManager.configure()
    }

    @MainActor
    func currentStatus() async -> Bool {
        BrightnessControl.getBrightness() > 0
    }

    @MainActor
    func currentInfo() async -> String {
        return ""
    }

    @MainActor
    func operateSwitch(isOn: Bool) async throws {
        BrightnessControl.setBrightness(isOn ? Preferences.shared.keyLightBrightness : 0)
    }

    func isVisible() -> Bool {
        return true
    }
}
