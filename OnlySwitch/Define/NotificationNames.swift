//
//  NotificationKeys.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/6/7.
//

import Foundation

extension Notification.Name {
    static let refreshSingleSwitchStatus = Notification.Name("refreshSingleSwitchStatus")
    static let changePTDuration = Notification.Name(rawValue:"ChangePTDurationNotification")
    static let showPopover = Notification.Name("showPopover")
    static let hidePopover = Notification.Name("hidePopover")
    static let shouldHidePopover = Notification.Name("shouldHidePopover")
    static let changeMenuBarIcon = Notification.Name("changeMenuBarIcon")
    static let changePopoverAppearance = Notification.Name("changePopoverAppearanceNotificationName")
    static let volumeChange = Notification.Name("volumeChange")
    static let soundWaveToggle = Notification.Name("soundWaveToggleNotification")
    static let changeSettings = Notification.Name("changeSettingNotification")
    static let spectra = Notification.Name(rawValue: "com.springradio.spectrabuffer")
    static let menubarCollapsable = Notification.Name(rawValue: "menubarCollapsableNotificationName")
    static let changeAutoMenubarCollapseTime = Notification.Name(rawValue: "changeAutoMenubarCollapseTime")
    static let toggleMenubarCollapse = Notification.Name(rawValue: "toggleMenubarCollapse")
    static let settingsWindowOpened = Notification.Name(rawValue: "settingsWindowOpened")
    static let settingsWindowClosed = Notification.Name(rawValue: "settingsWindowClosed")
    static let illegalRadioInfoNotification = Notification.Name("illegalRadioInfoNotification")
}
