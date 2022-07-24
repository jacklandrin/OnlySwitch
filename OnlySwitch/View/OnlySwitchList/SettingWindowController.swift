//
//  SettingWindowController.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/7/24.
//

import AppKit

protocol SettingWindowController {
    var settingsWindowPresented:Bool {get set}
    var settingsWindow:NSWindow? {get set}
    func receiveSettingWindowOperation()
    func showSettingsWindow()
}
