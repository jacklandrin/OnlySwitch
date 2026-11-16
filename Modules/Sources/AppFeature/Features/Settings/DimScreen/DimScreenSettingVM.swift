//
//  DimScreenSettingVM.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/8/13.
//

import Defines
import Extensions
import Foundation

@MainActor
class DimScreenSettingVM: ObservableObject {
    var durationSet = [0, 1, 5, 10, 15, 30, 45, 60]
    private var preferencesPublisher = PreferencesObserver.shared
    @Published private var preferences = PreferencesObserver.shared.preferences

    @Published var sliderValue: Float {
        didSet {
            let normalizedValue = normalizedSliderValue(sliderValue)
            if sliderValue != normalizedValue {
                sliderValue = normalizedValue
            }
            preferences.dimScreenPercent = normalizedValue
        }
    }

    /// Master switch for the whole brightness feature.
    @Published var isDisplayBrightnessEnabled: Bool = UserDefaults.isDisplayBrightnessEnabled() {
        didSet {
            guard isDisplayBrightnessEnabled != oldValue else { return }
            UserDefaults.standard.set(isDisplayBrightnessEnabled, forKey: UserDefaults.Key.displayBrightnessEnabled)
            NotificationCenter.default.post(name: .displayBrightnessEnabledDidChange, object: nil)
            // Rebuilds switch rows (Dim Screen `isVisible()`) and the Settings → Tabs list.
            NotificationCenter.default.post(name: .changeSettings, object: nil)
        }
    }

    /// Switch for DDC communication with external displays (issue #232).
    @Published var isExternalDisplayDDCEnabled: Bool = UserDefaults.isExternalDisplayDDCEnabled() {
        didSet {
            guard isExternalDisplayDDCEnabled != oldValue else { return }
            UserDefaults.standard.set(isExternalDisplayDDCEnabled, forKey: UserDefaults.Key.externalDisplayDDCEnabled)
            NotificationCenter.default.post(name: .externalDisplayDDCEnabledDidChange, object: nil)
        }
    }

    init() {
        sliderValue = PreferencesObserver.shared.preferences.dimScreenPercent
    }

    private func normalizedSliderValue(_ value: Float) -> Float {
        if value < 0.2 { // brightness isn't allowed below 20%
            return 0.2
        } else if value > 0.9 { // brightness isn't allowed above 90%
            return 0.9
        } else {
            return value.roundTo(places: 1)
        }
    }

    var currentDuration:Int {
        get {
            preferences.autoDimScreenTime
        }
        set {
            preferences.autoDimScreenTime = newValue
        }
    }

    var syncExternalBrightness:Bool {
        get {
            preferences.syncExternalBrightness
        }
        set {
            preferences.syncExternalBrightness = newValue
        }
    }
    
    func converTimeDescription(duration:Int) -> String {
        if duration == 0 {
            return "never".localized()
        } else if duration == 1 {
            return "1 minute".localized()
        } else if duration == 60 {
            return "1 hour".localized()
        } else {
            return "\(duration) " + "minutes".localized()
        }
    }
}
