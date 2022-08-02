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
        NotificationCenter.default.addObserver(forName: .settingsWindowOpened, object: nil, queue: .main, using: { notify in
            if let window = notify.object as? NSWindow {
                self.settingsWindow = window
            }
        })
        
        NotificationCenter.default.addObserver(forName: .settingsWindowClosed, object: nil, queue: .main, using: { _ in
            self.settingsWindowPresented = false
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
            }
        }
        NSApp.setActivationPolicy(.regular)
        NotificationCenter.default.post(name: .shouldHidePopover, object: nil)
    }
    
    class Coordinator:NSObject, NSWindowDelegate {
        func windowShouldClose(_ sender: NSWindow) -> Bool {
            onClose()
            return true
        }
        
        func onClose() {
            print("settings window close")
            DispatchQueue.main.async {
                NSApplication.shared.activate(ignoringOtherApps: true)
                NSApplication.shared.windows.first!.makeKeyAndOrderFront(self)
                NotificationCenter.default.post(name: .settingsWindowClosed, object: nil)
            }
            NSApplication.shared.setActivationPolicy(.accessory)
        }
    }
}

