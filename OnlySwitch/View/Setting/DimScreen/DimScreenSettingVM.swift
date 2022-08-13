//
//  DimScreenSettingVM.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/8/13.
//

import Foundation
class DimScreenSettingVM: ObservableObject {
    var durationSet = [0, 1, 5, 10, 15, 30, 45, 60]
    private var preferencesPublisher = PreferencesObserver.shared
    @Published private var preferences = PreferencesObserver.shared.preferences
    
    var sliderValue:Float{
        get {
            preferences.dimScreenPercent
        }
        set {
            if newValue < 0.1 { //brightness isn't allow to set below 10%
                preferences.dimScreenPercent = 0.1
            } else if newValue > 0.9 { //brightness isn't allow to set above 90%
                preferences.dimScreenPercent = 0.9
            } else {
                preferences.dimScreenPercent = newValue.roundTo(places: 1)
            }
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
