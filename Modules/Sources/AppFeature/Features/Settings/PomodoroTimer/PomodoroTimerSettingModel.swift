//
//  PomodoroTimerSettingModel.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/5/31.
//

import Foundation

struct PomodoroTimerSettingModel{
    var workDurationList = [25, 30, 35, 40, 45]
    var restDurationList = [5, 10, 15]
    var cycleCountList = [0, 1, 2, 3, 4]
    var alertSounds:[EffectSound] = [.alertBells, .bellNotification]
}
