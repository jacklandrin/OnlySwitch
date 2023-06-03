//
//  SettingVM.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/11.
//

import Foundation
import SwiftUI
import ComposableArchitecture

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
    case Evolution = "Evolution"
    case About = "About"
}


class SettingsVM: ObservableObject {
    
    static let shared = SettingsVM()
    
    @Published var settingItems:[SettingsItem]
    
    @Published var selection:SettingsItem? = .General

    let evolutionStore = Store(
        initialState: EvolutionReducer.State(),
        reducer: EvolutionReducer()
            .dependency(\.evolutionListService, .previewValue)
            ._printChanges()
        )

    init() {
        if #available(macOS 13.3, *) {
            settingItems = [
                .General,
                .Customize,
                .Shortcuts,
                .Evolution,
                .KeepAwake,
                .DimScreen,
                .Radio,
                .BackNoises,
                .AirPods,
                .PomodoroTimer,
                .HideMenubarIcons,
                .About]
        } else {
            settingItems = [
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
                .About]
        }
    }
    
    func toggleSliderbar() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NotificationCenter.default.post(name: .toggleSplitSettingsWindow, object: nil)
        }
    }
}


