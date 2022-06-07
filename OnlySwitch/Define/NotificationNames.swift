//
//  NotificationKeys.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/6/7.
//

import Foundation

extension Notification.Name {
    static let refreshSingleSwitchStatus = Notification.Name("refreshSingleSwitchStatus")
    static let changePTDuration = NSNotification.Name(rawValue:"ChangePTDurationNotification")
    static let showPopover = NSNotification.Name("showPopover")
    static let hidePopover = NSNotification.Name("hidePopover")
    static let shouldHidePopover = NSNotification.Name("shouldHidePopover")
    static let changeMenuBarIcon = NSNotification.Name("changeMenuBarIcon")
    static let changePopoverAppearance = NSNotification.Name("changePopoverAppearanceNotificationName")
}
