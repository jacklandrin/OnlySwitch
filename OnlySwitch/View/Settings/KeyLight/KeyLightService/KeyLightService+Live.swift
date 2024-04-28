//
//  KeyLightService+Live.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2024/4/28.
//

import Dependencies
import Foundation

extension KeyLightService: DependencyKey {
    static var liveValue: KeyLightService = Self(
        loadKeyboardManager: {
            KeyboardManager.configure()
        },
        setBrightness: { brightness in
            let keyLightBrightness = Float(brightness)
            BrightnessControl.setBrightness(keyLightBrightness)
            Preferences.shared.keyLightBrightness = keyLightBrightness
        },
        brightness: {
            let currentBrightness = BrightnessControl.getBrightness()
            let statusBrightness = currentBrightness > 0.1 ? currentBrightness : Preferences.shared.keyLightBrightness
            return Double(statusBrightness)
        },
        setAutoBrightness: { isAuto in
            BrightnessControl.enableAutoBrightness(isAuto)
        },
        autoBrightness: {
            BrightnessControl.isAutoBrightnessEnabled()
        }
    )
}
