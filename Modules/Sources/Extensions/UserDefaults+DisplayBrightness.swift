//
//  UserDefaults+DisplayBrightness.swift
//  Extensions
//
//  Gates for the display brightness feature and for DDC communication (issue #232).
//

import Foundation

public extension UserDefaults {
    /// Master switch for the whole display brightness feature (Brightness tab, brightness keys,
    /// remote brightness, Dim Screen). Defaults to `true`; a non-Bool stored value also reads as `true`.
    static func isDisplayBrightnessEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: Key.displayBrightnessEnabled) as? Bool ?? true
    }

    /// Whether OnlySwitch may use DDC to read or change external display brightness.
    /// When off, external displays fall back to software dimming.
    /// Defaults to `false`; a non-Bool stored value also reads as `false`.
    static func isExternalDisplayDDCEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: Key.externalDisplayDDCEnabled) as? Bool ?? false
    }
}
