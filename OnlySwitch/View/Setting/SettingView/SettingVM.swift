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

}

class SettingVM:ObservableObject {
    
    static let shared = SettingVM()
    
    @Published var settingItems:[SettingItem] = [.General,
                                                 .Customize,
                                                 .Shortcuts,
                                                 .Radio,
                                                 .AirPods,
                                                 .PomodoroTimer,
                                                 .HideMenubarIcons,
                                                 .About]
    
    @Published var selection:SettingItem? = .General
    
    
}
