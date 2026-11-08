//
//  RadioSettingVM.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/9.
//

import Combine
import Extensions

/// Playback preferences shown above the station lists. Stations themselves live in `RadioStationsFeature`.
@MainActor
class RadioSettingVM: ObservableObject {
    private var preferencesPublisher = PreferencesObserver.shared
    @Published private var preferences = PreferencesObserver.shared.preferences
    private var cancellables = Set<AnyCancellable>()

    var soundWaveEffectDisplay: Bool {
        get {
            preferences.soundWaveEffectDisplay
        }
        set {
            preferences.soundWaveEffectDisplay = newValue
        }
    }

    var sliderValue: Float {
        get {
            preferences.volume
        }
        set {
            preferences.volume = newValue
        }
    }

    var allowNotificationChangingStation: Bool {
        get {
            preferences.allNotificationChangingStation
        }
        set {
            preferences.allNotificationChangingStation = newValue
        }
    }

    var allowNotificationTrack: Bool {
        get {
            preferences.allNotificationTrack
        }
        set {
            preferences.allNotificationTrack = newValue
        }
    }

    init() {
        preferencesPublisher.$preferences.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        .store(in: &cancellables)
    }
}
