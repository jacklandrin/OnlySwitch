//
//  SettingVM.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/11.
//

import Foundation
import SwiftUI

let changeSettingNotification = NSNotification.Name("changeSettingNotification")
enum SettingItem:String {
    case AirPods = "AirPods"
    case Radio = "Radio"
    case PomodoroTimer = "Pomodoro Timer"
    case General = "General"
    case Customize = "Customize"
    case About = "About"
    
    
    func page() -> AnyView {
        switch self {
        case .AirPods:
            return AnyView(AirPodsSettingView())
        case .Radio:
            return AnyView(RadioSettingView())
        case .PomodoroTimer:
            return AnyView(PomodoroTimerSettingView())
        case .General:
            return AnyView(GeneralView())
        case .Customize:
            return AnyView(CustomizeView())
        case .About:
            return AnyView(AboutView())
        }
    }
}

class SettingVM:ObservableObject {
    @Published var settingItems:[SettingItem] = [.General, .Customize, .Radio, .AirPods, .PomodoroTimer,.About]
    @Published var selection:SettingItem?
}
