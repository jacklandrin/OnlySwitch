//
//  SettingVM.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/11.
//

import Foundation
import SwiftUI


enum SettingItem:String {
    case AirPods = "AirPods"
    case Radio = "Radio"
    case PomodoroTimer = "Pomodoro Timer"
    case General = "General"
    case Customize = "Customize"
    case Shortcuts = "Shortcuts"
    case HideMenubarIcons = "Hide Menu Bar Icons"
    case About = "About"
    
    
    func page() -> AnyView {
        switch self {
        case .AirPods:
            return AnyView(AirPodsSettingView())
        case .Radio:
            return AnyView(RadioSettingView())
        case .PomodoroTimer:
            return AnyView(PomodoroTimerSettingView())
        case .Shortcuts:
            return AnyView(ShortcutsView())
        case .General:
            return AnyView(GeneralView())
        case .Customize:
            return AnyView(CustomizeView())
        case .HideMenubarIcons:
            return AnyView(HideMenubarIconsSettingView())
        case .About:
            return AnyView(AboutView())
        }
    }
}

class SettingVM:ObservableObject {
    @Published var settingItems:[SettingItem] = [.General, .Customize, .Shortcuts, .Radio, .AirPods, .PomodoroTimer,.HideMenubarIcons,.About]
    @Published var selection:SettingItem?
    
    func onDisappear() {
        print("settings window disappear")
        NSApplication.shared.setActivationPolicy(.accessory)
        DispatchQueue.main.async {
            NSApplication.shared.activate(ignoringOtherApps: true)
            NSApplication.shared.windows.first!.makeKeyAndOrderFront(self)
            NotificationCenter.default.post(name: .settingsWindowClosed, object: nil)
        }
    }
}
