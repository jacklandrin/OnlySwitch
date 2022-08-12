//
//  KeepAwakeSettingVM.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/8/12.
//

import Foundation

class KeepAwakeSettingVM: ObservableObject {
    var durationSet = [0, 1, 5, 10, 15, 30, 45, 60]
    private var preferencesPublisher = PreferencesObserver.shared
    @Published private var preferences = PreferencesObserver.shared.preferences
    let timeZoneDifference = TimeInterval(TimeZone.current.secondsFromGMT()) - TimeZone.current.daylightSavingTimeOffset()
   
    var scheduleMode:Bool {
        get {
            preferences.autoStopKeepAwakeMode.boolValue
        }
        set {
            preferences.autoStopKeepAwakeMode = newValue.intValue
        }
    }
    
    var afterMode:Bool {
        get {
            !scheduleMode
        }
        set {
            scheduleMode = !newValue
        }
    }
    
    var currentDuration:Int {
        get {
            preferences.autoStopKeepAwakeTime
        }
        set {
            preferences.autoStopKeepAwakeTime = newValue
        }
    }
    
    
    var startDate:Date {
        get {
            let timestamp = preferences.autoStopKeepAwakeStartDate - timeZoneDifference
            return Date(timeIntervalSince1970: timestamp)
        }
        set {
            preferences.autoStopKeepAwakeStartDate = newValue.timeIntervalSince1970 + timeZoneDifference
        }
    }
    
    var endDate:Date {
        get {
            let timestamp = preferences.autoStopKeepAwakeEndDate - timeZoneDifference
            return Date(timeIntervalSince1970: timestamp)
        }
        
        set {
            preferences.autoStopKeepAwakeEndDate = newValue.timeIntervalSince1970 + timeZoneDifference
            print(preferences.autoStopKeepAwakeEndDate)
        }
    }
    
    func converTimeDescription(duration:Int) -> String {
        if duration == 0 {
            return "never".localized()
        } else if duration == 60 {
            return "1 hour".localized()
        } else {
            return "\(duration) " + "minites".localized()
        }
    }
    
    
}
