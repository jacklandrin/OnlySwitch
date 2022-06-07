//
//  Preference.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/6/7.
//

import Foundation

struct Preferences {
    static var shared = Preferences()
    // MARK: - Pomodoro Timer
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
    
    // MARK: - AirPods
    @UserDefaultValue(key: UserDefaults.Key.AirPodsAddress, defaultValue: nil)
    var airPodsAddress:String?
    
    // MARK: - Radio
    @UserDefaultValue(key: UserDefaults.Key.volume, defaultValue: 1.0)
    var volume:Float
    {
        didSet {
            let userInfo = [ "newValue" : volume ]
            NotificationCenter.default.post(name: .volumeChange, object: nil, userInfo: userInfo)
        }
    }
    
    @UserDefaultValue(key: UserDefaults.Key.soundWaveEffectDisplay, defaultValue: true)
    var soundWaveEffectDisplay:Bool{
        didSet {
            NotificationCenter.default.post(name: .soundWaveToggle, object: nil)
            NotificationCenter.default.post(name: .refreshSingleSwitchStatus, object: SwitchType.radioStation)
            
        }
    }
    
    @UserDefaultValue(key: UserDefaults.Key.radioStation, defaultValue: nil)
    var radioStationID:String?
}
