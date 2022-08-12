//
//  BackNoisesSettingVM.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/8/11.
//

import Foundation
import Combine

class BackNoisesSettingVM:ObservableObject {
    
    private var cancellables = Set<AnyCancellable>()
    private var preferencesPublisher = PreferencesObserver.shared
    @Published private var preferences = PreferencesObserver.shared.preferences
    @Published private var backNoisesTrackManager = BackNoisesTrackManager.shared
    
    var durationSet = [0, 5, 10, 15, 30]
    
    var trackList:[String] {
        backNoisesTrackManager.trackList.map { $0.rawValue }
    }
    
    var currentTrack:String {
        backNoisesTrackManager.currentTrack.rawValue
    }
    
    var automaticallyStopPlayNoise:Int {
        get {
            preferences.automaticallyStopPlayNoiseTime
        }
        
        set {
            preferences.automaticallyStopPlayNoiseTime = newValue
        }
    }
    
    var sliderValue:Float {
        get {
            preferences.volume
        }
        set {
            preferences.volume = newValue
        }
    }
    
    init() {
        preferencesPublisher.$preferences.sink{_ in
            self.objectWillChange.send()
        }.store(in: &cancellables)
        
        backNoisesTrackManager.objectWillChange.sink{ _ in
            self.objectWillChange.send()
        }.store(in: &cancellables)
    }
    
    deinit{
        cancellables.removeAll()
    }
    
    func selectTrack(index:Int) {
        let track = backNoisesTrackManager.trackList[index]
        backNoisesTrackManager.currentTrack = track
        objectWillChange.send()
    }
    
    func converTimeDescription(duration:Int) -> String {
        if duration == 0 {
            return "never".localized()
        } else {
            return "\(duration) " + "minites".localized()
        }
    }
}
