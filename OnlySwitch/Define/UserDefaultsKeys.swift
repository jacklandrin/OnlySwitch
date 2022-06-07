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
    }
}
