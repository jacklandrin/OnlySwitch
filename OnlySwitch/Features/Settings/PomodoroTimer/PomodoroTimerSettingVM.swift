//
//  PomodoroTimerSettingVM.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/26.
//

import Foundation

@MainActor
class PomodoroTimerSettingVM:ObservableObject {
    @Published private var model = PomodoroTimerSettingModel()
    @Published private var preferences = Preferences.shared
    
    var workDurationList:[Int] {
        model.workDurationList
    }
    
    var restDurationList:[Int] {
        model.restDurationList
    }
    
    var cycleCountList:[Int] {
        model.cycleCountList
    }
    
    var alertSounds:[EffectSound] {
        model.alertSounds
    }
    
    var workDuration:Int {
        get {
            return preferences.workDuration
        }
        set {
            preferences.workDuration = newValue
        }
    }
    
    var restDuration:Int {
        get {
            return preferences.restDuration
        }
        set {
            preferences.restDuration = newValue
        }
    }
    
    var restAlert:String {
        get {
            return preferences.restAlert
        }
        set {
            preferences.restAlert = newValue
        }
    }
    
    var workAlert:String {
        get {
            return preferences.workAlert
        }
        set {
            preferences.workAlert = newValue
        }
    }
    
    var allowNotificationAlert:Bool {
        get {
            return preferences.allowNotificationAlert
        }
        set {
            preferences.allowNotificationAlert = newValue
        }
    }
    
    var cycleCount:Int {
        get {
            return preferences.cycleCount
        }
        set {
            preferences.cycleCount = newValue
        }
    }
}
