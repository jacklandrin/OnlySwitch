//
//  SettingVM.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/11.
//

import Foundation
import SwiftUI


enum SettingsItem:String {
    case AirPods = "AirPods"
    case Radio = "Radio"
    case PomodoroTimer = "Pomodoro Timer"
    case General = "General"
    case Customize = "Customize"
    case Shortcuts = "Shortcuts"
    case HideMenubarIcons = "Hide Menu Bar Icons"
    case BackNoises = "Back Noises"
    case KeepAwake = "Keep Awake"
    case DimScreen = "Dim Screen"
    case Dev = "Dev"
    case About = "About"

    @ViewBuilder
    var page: some View {
        switch self {
        case .AirPods:
            AirPodsSettingView()
        case .Radio:
            RadioSettingView()
        case .PomodoroTimer:
            PomodoroTimerSettingView()
        case .Shortcuts:
            ShortcutsView()
        case .General:
            GeneralView()
        case .Customize:
            CustomizeView()
        case .HideMenubarIcons:
            HideMenubarIconsSettingView()
        case .BackNoises:
            BackNoisesSettingView()
        case .KeepAwake:
            KeepAwakeSettingView()
        case .DimScreen:
            DimScreenSettingView()
        case .Dev:
            DevView()
        case .About:
            AboutView()
        }
    }

}

class SettingsVM:ObservableObject {
    
    static let shared = SettingsVM()
    
    @Published var settingItems:[SettingsItem] = [
                                                 .General,
                                                 .Customize,
                                                 .Shortcuts,
                                                 .KeepAwake,
                                                 .DimScreen,
                                                 .Radio,
                                                 .BackNoises,
                                                 .AirPods,
                                                 .PomodoroTimer,
                                                 .HideMenubarIcons,
//                                                 .Dev,
                                                 .About]
    
    @Published var selection:SettingsItem? = .General

}
