import Dependencies
import DisplayBrightness
import Extensions
import Foundation

@MainActor
enum DisplayBrightnessSettingsPersistence {
    static func load() -> BrightnessSettings {
        let defaults = UserDefaults.standard
        func flag(_ key: String, default fallback: Bool) -> Bool { defaults.object(forKey: key) as? Bool ?? fallback }
        return .init(smoothTransitions: flag(UserDefaults.Key.smoothBrightnessTransitions, default: true),
                     combinedDimming: flag(UserDefaults.Key.combinedBrightnessDimming, default: true),
                     syncNativeBrightness: flag(UserDefaults.Key.syncExternalBrightness, default: false),
                     allowZeroSoftwareBrightness: flag(UserDefaults.Key.allowZeroSoftwareBrightness, default: false),
                     controlWithBrightnessKeys: flag(UserDefaults.Key.controlWithBrightnessKeys, default: true))
    }
    static func save(_ settings: BrightnessSettings) {
        let defaults = UserDefaults.standard
        defaults.set(settings.smoothTransitions, forKey: UserDefaults.Key.smoothBrightnessTransitions)
        defaults.set(settings.combinedDimming, forKey: UserDefaults.Key.combinedBrightnessDimming)
        defaults.set(settings.syncNativeBrightness, forKey: UserDefaults.Key.syncExternalBrightness)
        defaults.set(settings.allowZeroSoftwareBrightness, forKey: UserDefaults.Key.allowZeroSoftwareBrightness)
        defaults.set(settings.controlWithBrightnessKeys, forKey: UserDefaults.Key.controlWithBrightnessKeys)
    }
}

extension DisplayBrightnessClient {
    static var app: Self {
        Self(scan: { await DisplayBrightnessService.shared.scan() },
             apply: { try await DisplayBrightnessService.shared.apply($0) },
             events: { await DisplayBrightnessService.shared.events() },
             loadSettings: { await DisplayBrightnessSettingsPersistence.load() },
             saveSettings: { settings in
                 await DisplayBrightnessSettingsPersistence.save(settings)
                 await DisplayBrightnessService.shared.updateSettings(settings)
             },
             resetSoftwareDimming: { await DisplayBrightnessService.shared.resetSoftwareDimming() },
             requestKeyboardAccess: { await DisplayBrightnessService.shared.requestKeyboardAccess() })
    }
}
