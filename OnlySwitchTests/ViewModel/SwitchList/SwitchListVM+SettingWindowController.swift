//
//  SwitchListVM+SettingWindowController.swift
//  OnlySwitchTests
//
//  Created by Jacklandrin on 2022/7/24.
//

import AppKit

extension SwitchListVM:SettingWindowController {
    struct Holder {
        static var _settingsWindowPresented = false
        static var _settingsWindow:NSWindow?
    }
    
    var settingsWindowPresented: Bool {
        get {
            return Holder._settingsWindowPresented
        }
        set {
            Holder._settingsWindowPresented = newValue
        }
    }
    
    var settingsWindow: NSWindow? {
        get {
            return Holder._settingsWindow
        }
        set {
            Holder._settingsWindow = newValue
        }
    }
    
    func receiveSettingWindowOperation() {
        
    }
    
    func showSettingsWindow() {
        
    }
    
    
}
