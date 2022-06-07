//
//  UserDefaultsKeys.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/6/7.
//

import Foundation

extension UserDefaults {
    struct Key {
        //PomodoroTimer
        static let WorkDuration = "WorkDurationKey"
        static let RestDuration = "RestDurationKey"
        static let RestAlert = "RestAlertKey"
        static let WorkAlert = "WorkAlertKey"
        static let AllowNotificationAlert = "AllowNotificationAlertKey"
        static let PTimerCycleCount = "PTimerLoopCountKey"
        //AirPods
        static let AirPodsAddress = "AirPodsAddressKey"
        //Radio
        static let soundWaveEffectDisplay = "soundWaveEffectDisplayKey"
        static let volume = "volumeKey"
        static let hasRunRadio = "hasRunRadioKey"
        static let radioStation = "radioStationKey"
        //Shortcuts
        static let shortcutsDic = "shortcutsDicKey"
    }
}
