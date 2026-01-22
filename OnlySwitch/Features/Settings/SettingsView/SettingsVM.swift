//
//  SettingVM.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/11.
//

import Foundation
import SwiftUI
import ComposableArchitecture

enum SettingsItem: String, CaseIterable {
    case General = "General"
    case Customize = "Customize"
    case Shortcuts = "Shortcuts"
    case Evolution = "Evolution"
    case ModelProviders = "Model Providers"
    case AirPods = "AirPods"
    case Radio = "Radio"
    case Authenticator = "Authenticator"
    case PomodoroTimer = "Pomodoro Timer"
    case HideMenubarIcons = "Hide Menu Bar Icons"
    case BackNoises = "Back Noises"
    case KeepAwake = "Keep Awake"
    case DimScreen = "Dim Screen"
    case NightShift = "Night Shift"
    case KeyLight = "Key Light"
    case About = "About"
}

@MainActor
class SettingsVM: ObservableObject {

    static let shared = SettingsVM()

    @Published var settingItems: [SettingsItem]

    @Published var selection: SettingsItem? = .General

    var evolutionStore = Store(
        initialState: EvolutionReducer.State()) {
            EvolutionReducer()
                ._printChanges()
        } withDependencies: {
            $0.evolutionListService = .liveValue
        }

    var keyLightStore = Store(
        initialState: KeyLightFeature.State()) {
            KeyLightFeature()
                ._printChanges()
        }

    init() {
        settingItems = SettingsItem.allCases
        if #available(macOS 26.0, *) {} else {
            if let index = settingItems.firstIndex(of: .ModelProviders) {
                settingItems.remove(at: index)
            }
        }
    }

    func toggleSliderbar() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NotificationCenter.default.post(name: .toggleSplitSettingsWindow, object: nil)
        }
    }
}

