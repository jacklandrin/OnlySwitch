//
//  SwitchListVM+SettingWindowController.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/7/24.
//

import Foundation
import AppKit

extension SwitchListVM: SettingWindowController {
    struct Holder {
        static var _settingsWindowPresented = false
        static var _settingsWindow:NSWindow?
        static var _coordinator:Coordinator = Coordinator()
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
            newValue?.delegate = coodinator
            Holder._settingsWindow = newValue
        }
    }
    
    var coodinator:Coordinator {
        return Holder._coordinator
    }
    
    func receiveSettingWindowOperation() {
        NotificationCenter.default.addObserver(forName: .settingsWindowOpened,
                                               object: nil,
                                               queue: .main,
                                               using: { notify in
            if let window = notify.object as? NSWindow {
                self.settingsWindow = window
//                self.settingsWindow?.center()
                self.settingsWindow?.delegate = self.coodinator
            }
        })
        
        NotificationCenter.default.addObserver(forName: .settingsWindowClosed,
                                               object: nil,
                                               queue: .main,
                                               using: { _ in
            self.settingsWindowPresented = false
            NSApp.activate(ignoringOtherApps: false)
            self.settingsWindow = nil
        })
    }
    
    func showSettingsWindow() {
        if let window = self.settingsWindow {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(self)
        } else {
            if let url = URL(string: "onlyswitch://SettingsWindow") {
                NSWorkspace.shared.open(url)
                self.settingsWindowPresented = true
                print("new setting window appears")
            }
        }
        
        NotificationCenter.default.post(name: .shouldHidePopover, object: nil)
        NSApp.setActivationPolicy(.regular)
    }
    
    class Coordinator:NSObject, NSWindowDelegate {
        func windowShouldClose(_ sender: NSWindow) -> Bool {
            onClose()
            return true
        }
        
        func onClose() {
            print("settings window closing")
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first!.makeKeyAndOrderFront(self)
            NotificationCenter.default.post(name: .settingsWindowClosed, object: nil)
            NSApplication.shared.setActivationPolicy(.accessory)
        }
    }
}

