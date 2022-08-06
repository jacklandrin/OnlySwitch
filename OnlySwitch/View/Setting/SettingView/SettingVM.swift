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

    var page: AnyView {
        switch self {
        case .AirPods:
            return AirPodsSettingView().eraseToAnyView()
        case .Radio:
            return RadioSettingView().eraseToAnyView()
        case .PomodoroTimer:
            return PomodoroTimerSettingView().eraseToAnyView()
        case .Shortcuts:
            return ShortcutsView().eraseToAnyView()
        case .General:
            return GeneralView().eraseToAnyView()
        case .Customize:
            return CustomizeView().eraseToAnyView()
        case .HideMenubarIcons:
            return HideMenubarIconsSettingView().eraseToAnyView()
        case .About:
            return AboutView().eraseToAnyView()
        }
    }

}

class SettingVM:ObservableObject {
    
    static let shared = SettingVM()
    
    @Published var settingItems:[SettingItem] = [
                                                 .General,
                                                 .Customize,
                                                 .Shortcuts,
                                                 .Radio,
                                                 .AirPods,
                                                 .PomodoroTimer,
                                                 .HideMenubarIcons,
                                                 .About]
    
    @Published var selection:SettingItem? = .General
    
}
