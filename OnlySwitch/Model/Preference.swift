//
//  Preference.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/6/7.
//

import Foundation

struct Preferences {
    static var shared = Preferences()
    @UserDefaultValue(key: UserDefaults.Key.WorkDuration, defaultValue: 25 * 60)
    var workDuration:Int
    {
        didSet {
            NotificationCenter.default.post(name: .changePTDuration, object: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NotificationCenter.default.post(name: .refreshSingleSwitchStatus, object: SwitchType.pomodoroTimer)
            }
        }
    }
    
    @UserDefaultValue(key: UserDefaults.Key.RestDuration, defaultValue: 5 * 60)
    var restDuration:Int {
        didSet {
            NotificationCenter.default.post(name: .changePTDuration, object: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NotificationCenter.default.post(name: .refreshSingleSwitchStatus, object: SwitchType.pomodoroTimer)
            }
        }
    }
    
    @UserDefaultValue(key: UserDefaults.Key.RestAlert, defaultValue: EffectSound.alertBells.rawValue)
    var restAlert:String
    
    @UserDefaultValue(key: UserDefaults.Key.WorkAlert, defaultValue: EffectSound.bellNotification.rawValue)
    var workAlert:String
    
    @UserDefaultValue(key: UserDefaults.Key.AllowNotificationAlert, defaultValue: true)
    var allowNotificationAlert:Bool
    
    @UserDefaultValue(key: UserDefaults.Key.PTimerCycleCount, defaultValue: 1)
    var cycleCount:Int
}
