//
//  UserDefaultsKeys.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/6/7.
//

import Foundation

extension UserDefaults {
    struct Key {
        //General
        static let menubarIcon = "menubarIconKey"
        static let appearanceColumnCount = "appearanceColumnCountKey"
        static let showAds = "showAdsKey"
        //Evolution
        static let evolutionIDs = "evolutionIDsKey"
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
        static let allowNotificationChangingStation = "allowNotificationChangingStationKey"
        static let allowNotificationTrack = "allowNotificationTrack"
        static let radioEnable = "radioEnable"
        //Hidden menubar
        static let isMenubarCollapse = "isMenubarCollapseKey"
        static let autoCollapseMenubarTime = "autoCollapseMenubarTimeKey"
        static let menubarCollapsable = "menubarCollapsableKey"
        //Switch
        static let SwitchState = "SwitchStateKey"
        //Shortcuts
        static let shortcutsDic = "shortcutsDicKey"
        //Sort
        static let orderWeight = "orderWeightKey"
        //BackNoises
        static let backNoisesTrack = "backNoisesTrackKey"
        static let automaticallyStopPlayNoiseTime = "automaticallyStopPlayNoiseTimeKey"
        //Keep Awake
        static let autoStopKeepAwakeMode = "autoStopKeepAwakeModeKey"
        static let autoStopKeepAwakeTime = "autoStopKeepAwakeTimeKey"
        static let autoStopKeepAwakeStartDate = "autoStopKeepAwakeStartDateKey"
        static let autoStopKeepAwakeEndDate = "autoStopKeepAwakeEndDateKey"
        static let KeepAwakeKey = "KeepAwakeKey"
        //Dim Screen
        static let autoDimScreenTime = "autoDimScreenTimeKey"
        static let dimScreenPercent = "dimScreenPercentKey"
        //Night Shift
        static let nightShiftStrength = "nightShiftStrengthKey"
        static let nightShiftStartDate = "nightShiftStartDateKey"
        static let nightShiftEndDate = "nightShiftEndDateKey"
        static let isNightShiftScheduleOn = "isNightShiftScheduleOnKey"
        //Hide Windows
        static let windowsHidden = "windowsHiddenKey"
        static let hiddenWindowsInfo = "hiddenWindowsInfoKey"
        //others
        static let newestVersion = "newestVersionKey"
        static let systemLangPriority = "systemLangPriority"
        static let NSVolume = "NSVolumeKey"
        static let ASVolume = "ASVolumeKey"
        static let MicVolume = "MicVolumeKey"
        static let ScreenSaverInterval = "ScreenSaverIntervalKey"
        static let AppLanguage = "app_lang"
    }
}
