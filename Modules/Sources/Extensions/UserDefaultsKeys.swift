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
        public static let showDesktopPet = "showDesktopPetKey"
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
        //Sound Mixer
        public static let soundMixerEnabled = "soundMixerEnabledKey"
        // System Monitor
        public static let systemMonitorPreferences = "systemMonitorPreferencesKey"
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
        public static let syncExternalBrightness = "syncExternalBrightnessKey"
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
        public static let claudeAPI = "claudeAPIKey"
        //KeyLight
        public static let keyLightBrightness = "keyLightBrightnessKey"
        // Authenticator
        public static let authenticatorEnabled = "authenticatorEnabledKey"
        public static let authenticatorAccounts = "authenticatorAccountsKey"
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
        public static let canPlayEffectSound = "canPlayESKey"
        public static let onlyRemoteCampaignAcknowledgedVersion = "onlyRemoteCampaignAcknowledgedVersionKey"

        /// `UserDefaults.standard` keys included in a settings backup.
        /// Deliberately excludes: API keys and authenticator secrets (never leave the device),
        /// hardware identifiers (AirPodsAddress), and internal/runtime state that isn't a
        /// user-facing setting (hasRunRadio, radioStation, window session state, caches,
        /// version-check bookkeeping, live volume mirrors).
        public static let exportableKeys: [String] = [
            menubarIcon, appearanceColumnCount, showAds, showDesktopPet,
            evolutionIDs,
            WorkDuration, RestDuration, RestAlert, WorkAlert, AllowNotificationAlert, PTimerCycleCount,
            soundWaveEffectDisplay, volume, allowNotificationChangingStation, allowNotificationTrack, radioEnable,
            isMenubarCollapse, autoCollapseMenubarTime, menubarCollapsable,
            SwitchState,
            shortcutsDic,
            orderWeight, onlyControlOrderWeight,
            soundMixerEnabled,
            systemMonitorPreferences,
            backNoisesTrack, automaticallyStopPlayNoiseTime,
            autoStopKeepAwakeMode, autoStopKeepAwakeTime, autoStopKeepAwakeStartDate, autoStopKeepAwakeEndDate, KeepAwakeKey,
            autoDimScreenTime, dimScreenPercent, syncExternalBrightness,
            nightShiftStrength, nightShiftStartDate, nightShiftEndDate, isNightShiftScheduleOn,
            sticker,
            currentAIModel, ollamaUrl, openAIHost,
            keyLightBrightness,
            authenticatorEnabled,
            ScreenSaverInterval, checkUpdateOnLaunch, hideMenuAfterRunning, canPlayEffectSound,
        ]

        /// Keys stored in the shared app-group suite (`<TeamPrefix>OnlySwitch.shared`), not in `.standard`.
        public static let sharedExportableKeys: [String] = [AppLanguage, systemLangPriority]
    }
}
