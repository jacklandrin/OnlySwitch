//
//  DimScreenSettingVM.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/8/13.
//

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
