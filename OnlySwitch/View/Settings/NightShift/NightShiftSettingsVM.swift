//
//  NightShiftSettingsReducer.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2023/6/19.
//

import Foundation

@MainActor
class NightShiftSettingsVM: ObservableObject {

    private var preferencesPublisher = PreferencesObserver.shared
    @Published private var preferences = PreferencesObserver.shared.preferences
    private let timeZoneDifference = TimeInterval(TimeZone.current.secondsFromGMT()) - TimeZone.current.daylightSavingTimeOffset()

    var sliderValue: Float{
        get {
            preferences.nightShiftStrength
        }
        set {
            if newValue < 0.1 { // Strength isn't allow to set below 10%
                preferences.nightShiftStrength = 0.1
            } else {
                preferences.nightShiftStrength = newValue.roundTo(places: 1)
            }
        }
    }

    var isScheduleOn: Bool {
        get {
            preferences.isNightShiftScheduleOn
        }
        set {
            preferences.isNightShiftScheduleOn = newValue
        }
    }

    var startDate: Date {
        get {
            let timestamp = preferences.nightShiftStartDate - timeZoneDifference
            return Date(timeIntervalSince1970: timestamp)
        }
        set {
            preferences.nightShiftStartDate = newValue.timeIntervalSince1970 + timeZoneDifference
        }
    }

    var endDate: Date {
        get {
            let timestamp = preferences.nightShiftEndDate - timeZoneDifference
            return Date(timeIntervalSince1970: timestamp)
        }

        set {
            preferences.nightShiftEndDate = newValue.timeIntervalSince1970 + timeZoneDifference
        }
    }

    var isTomorrow: Bool {
        endDate.timeIntervalSince1970 <= startDate.timeIntervalSince1970
    }

}
