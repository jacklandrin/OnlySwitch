//
//  UserDefaultsKeys.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/6/7.
//

import Foundation

public extension UserDefaults {
    struct Key {
        //General
        public static let menubarIcon = "menubarIconKey"
        public static let appearanceColumnCount = "appearanceColumnCountKey"
        public static let showAds = "showAdsKey"
        //Evolution
        public static let evolutionIDs = "evolutionIDsKey"
        //PomodoroTimer
        public static let WorkDuration = "WorkDurationKey"
        public static let RestDuration = "RestDurationKey"
        public static let RestAlert = "RestAlertKey"
        public static let WorkAlert = "WorkAlertKey"
        public static let AllowNotificationAlert = "AllowNotificationAlertKey"
        public static let PTimerCycleCount = "PTimerLoopCountKey"
        //AirPods
        public static let AirPodsAddress = "AirPodsAddressKey"
        //Radio
        public static let soundWaveEffectDisplay = "soundWaveEffectDisplayKey"
        public static let volume = "volumeKey"
        public static let hasRunRadio = "hasRunRadioKey"
        public static let radioStation = "radioStationKey"
        public static let allowNotificationChangingStation = "allowNotificationChangingStationKey"
        public static let allowNotificationTrack = "allowNotificationTrack"
        public static let radioEnable = "radioEnable"
        //Hidden menubar
        public static let isMenubarCollapse = "isMenubarCollapseKey"
        public static let autoCollapseMenubarTime = "autoCollapseMenubarTimeKey"
        public static let menubarCollapsable = "menubarCollapsableKey"
        //Switch
        public static let SwitchState = "SwitchStateKey"
        //Shortcuts
        public static let shortcutsDic = "shortcutsDicKey"
        //Sort
        public static let orderWeight = "orderWeightKey"
        public static let onlyControlOrderWeight = "onlyControlOrderWeightKey"
        //BackNoises
        public static let backNoisesTrack = "backNoisesTrackKey"
        public static let automaticallyStopPlayNoiseTime = "automaticallyStopPlayNoiseTimeKey"
        //Keep Awake
        public static let autoStopKeepAwakeMode = "autoStopKeepAwakeModeKey"
        public static let autoStopKeepAwakeTime = "autoStopKeepAwakeTimeKey"
        public static let autoStopKeepAwakeStartDate = "autoStopKeepAwakeStartDateKey"
        public static let autoStopKeepAwakeEndDate = "autoStopKeepAwakeEndDateKey"
        public static let KeepAwakeKey = "KeepAwakeKey"
        //Dim Screen
        public static let autoDimScreenTime = "autoDimScreenTimeKey"
        public static let dimScreenPercent = "dimScreenPercentKey"
        //Night Shift
        public static let nightShiftStrength = "nightShiftStrengthKey"
        public static let nightShiftStartDate = "nightShiftStartDateKey"
        public static let nightShiftEndDate = "nightShiftEndDateKey"
        public static let isNightShiftScheduleOn = "isNightShiftScheduleOnKey"
        //Hide Windows
        public static let windowsHidden = "windowsHiddenKey"
        public static let hiddenWindowsInfo = "hiddenWindowsInfoKey"
        //Sticker
        public static let sticker = "stickerKey"
        //OnlyAgent
        public static let currentAIModel = "currentAIModelKey"
        public static let ollamaUrl = "ollamaUrlKey"
        public static let ollamaModels = "ollamaModelsKey"
        public static let openAIAPI = "openAIAPIKey"
        public static let openAIHost = "openAIHostKey"
        public static let geminiAPI = "geminiAPIKey"
        //KeyLight
        public static let keyLightBrightness = "keyLightBrightnessKey"
        //others
        public static let newestVersion = "newestVersionKey"
        public static let systemLangPriority = "systemLangPriority"
        public static let NSVolume = "NSVolumeKey"
        public static let ASVolume = "ASVolumeKey"
        public static let MicVolume = "MicVolumeKey"
        public static let ScreenSaverInterval = "ScreenSaverIntervalKey"
        public static let AppLanguage = "app_lang"
        public static let checkUpdateOnLaunch = "checkUpdateOnLaunchKey"
        public static let hideMenuAfterRunning = "hideMenuAfterRunningKey"
    }
}
