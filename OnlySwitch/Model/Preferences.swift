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
            NotificationCenter.default.post(name: .refreshSingleSwitchStatus, object: SwitchType.backNoises)
        }
    }
    
    @UserDefaultValue(key: UserDefaults.Key.allowNotificationChangingStation, defaultValue: false)
    var allNotificationChangingStation:Bool
    
    @UserDefaultValue(key: UserDefaults.Key.allowNotificationTrack, defaultValue: false)
    var allNotificationTrack:Bool
    
    @UserDefaultValue(key: UserDefaults.Key.radioEnable, defaultValue: true)
    var radioEnable:Bool {
        didSet {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NotificationCenter.default.post(name: .changeSettings, object: nil)
            }
        }
    }
    
    @UserDefaultValue(key: UserDefaults.Key.radioStation, defaultValue: nil)
    var radioStationID:String?
    
    // MARK: - Shortcuts
    @UserDefaultValue(key: UserDefaults.Key.shortcutsDic, defaultValue: nil)
    var shortcutsDic:[String:Bool]?
    
    // MARK: - General
    @UserDefaultValue(key: UserDefaults.Key.menubarIcon, defaultValue: "menubar_0")
    var currentMenubarIcon:String
    {
        didSet {
            NotificationCenter.default.post(name: .changeMenuBarIcon, object: currentMenubarIcon)
        }
    }
    
    @UserDefaultValue(key: UserDefaults.Key.appearanceColumnCount, defaultValue: SwitchListAppearance.single.rawValue)
    var currentAppearance:String {
        didSet {
            NotificationCenter.default.post(name: .changePopoverAppearance, object: nil)
        }
    }
    
    @UserDefaultValue(key: UserDefaults.Key.showAds, defaultValue: true)
    var showAds:Bool {
        didSet {
            NotificationCenter.default.post(name: .changeSettings, object: nil)
        }
    }
    
    // MARK: - Hidden Menubar
    @UserDefaultValue(key: UserDefaults.Key.menubarCollapsable, defaultValue: true)
    var menubarCollaspable:Bool {
        didSet {
            NotificationCenter.default.post(name: .menubarCollapsable, object: menubarCollaspable)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NotificationCenter.default.post(name: .changeSettings, object: nil)
            }
        }
    }
    
    @UserDefaultValue(key: UserDefaults.Key.autoCollapseMenubarTime, defaultValue: 0)
    var autoCollapseMenubarTime:Int {
        didSet {
            NotificationCenter.default.post(name: .changeAutoMenubarCollapseTime, object: autoCollapseMenubarTime)
        }
    }
    
    var isAutoCollapseMenubar:Bool {
        autoCollapseMenubarTime != 0
    }
    
    // MARK: - BackNoises
    @UserDefaultValue(key: UserDefaults.Key.backNoisesTrack, defaultValue: "White Noises")
    var backNoisesTrack:String
    
    @UserDefaultValue(key: UserDefaults.Key.automaticallyStopPlayNoiseTime, defaultValue: 0)
    var automaticallyStopPlayNoiseTime:Int {
        didSet {
            NotificationCenter.default.post(name: .changeAutoStopNoiseTime, object: nil)
        }
    }
    
    var isAutoStopNoise:Bool {
        automaticallyStopPlayNoiseTime != 0
    }
    
    @UserDefaultValue(key: UserDefaults.Key.autoStopKeepAwakeMode, defaultValue: 1)
    var autoStopKeepAwakeMode:Int
    {
        didSet {
            NotificationCenter.default.post(name: .changeKeepAwakeSetting, object: nil)
        }
    }
    
    @UserDefaultValue(key: UserDefaults.Key.autoStopKeepAwakeTime, defaultValue: 0)
    var autoStopKeepAwakeTime:Int
    {
        didSet {
            NotificationCenter.default.post(name: .changeKeepAwakeSetting, object: nil)
        }
    }
    
    @UserDefaultValue(key: UserDefaults.Key.autoStopKeepAwakeStartDate, defaultValue: 0.0)
    var autoStopKeepAwakeStartDate:Double
    {
        didSet {
            NotificationCenter.default.post(name: .changeKeepAwakeSetting, object: nil)
        }
    }
    
    @UserDefaultValue(key: UserDefaults.Key.autoStopKeepAwakeEndDate, defaultValue: 0.0)
    var autoStopKeepAwakeEndDate:Double
    {
        didSet {
            NotificationCenter.default.post(name: .changeKeepAwakeSetting, object: nil)
        }
    }
    
    // MARK: - Dim Screen
    
    @UserDefaultValue(key: UserDefaults.Key.autoDimScreenTime, defaultValue: 0)
    var autoDimScreenTime:Int {
        didSet {
            NotificationCenter.default.post(name: .changeDimScreenSetting, object: nil)
        }
    }
    
    @UserDefaultValue(key: UserDefaults.Key.dimScreenPercent, defaultValue: 0.5)
    var dimScreenPercent:Float {
        didSet {
            NotificationCenter.default.post(name: .changeDimScreenSetting, object: nil)
        }
    }
    
    
}
