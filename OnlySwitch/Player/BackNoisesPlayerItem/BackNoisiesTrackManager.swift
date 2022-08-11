//
//  BackNoisiesTrackManager.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/8/11.
//

import Foundation

class BackNoisesTrackManager {
    enum Tracks:String {
        case WhiteNoise = "White Noise"
        case PinkNoise = "Pink Noise"
        case Brownian = "Brownian"
        case MeadowBirds = "Meadow Birds"
        case ForestWalking = "Forest Walking"
        case SoftRain = "Soft Rain"
        case MotorBoat = "Motor Boat"
        case HarborWave = "Harbor Wave"
        case CrowdUrban = "Crowd Urban"
        case Meditation = "Meditation"
    }
    
    static let shared = BackNoisesTrackManager()
    var currentBackNoisesItem = BackNoisesPlayerItemViewModel()
    
    var currentTrack:Tracks {
        get {
            Tracks(rawValue: Preferences.shared.backNoisesTrack) ?? .WhiteNoise
        }
        set {
            Preferences.shared.backNoisesTrack = newValue.rawValue
            setPlayItem(track: newValue)
        }
    }
    
    private var currentTrackIndex:Int {
        trackList.indices.filter { trackList[$0] == currentTrack }.first ?? 0
    }
    
    
    let trackList:[Tracks] = [
        .WhiteNoise,
        .PinkNoise,
        .Brownian,
        .MeadowBirds,
        .ForestWalking,
        .SoftRain,
        .MotorBoat,
        .HarborWave,
        .CrowdUrban,
        .Meditation
    ]
    
    init() {
//        self.currentTrack = .WhiteNoise
        setPlayItem(track: currentTrack)
    }

    func setPlayItem(track:Tracks) {
        guard let trackURL = Bundle.main.path(forResource: track.rawValue, ofType: "mp3") else {
            return
        }
//        currentBackNoisesItem = BackNoisesPlayerItemViewModel()
        currentBackNoisesItem.url = URL(fileURLWithPath: trackURL)
        currentBackNoisesItem.title = track.rawValue
        currentBackNoisesItem.changeToPreviousTrack = {
            self.changeTrack(action: .previous)
        }
        
        currentBackNoisesItem.changeToNextTrack = {
            self.changeTrack(action: .next)
        }
    }
    
    func changeTrack(action:ChangeTrackAction) {
        PlayerManager.shared.player.stop()
        let isPlaying = currentBackNoisesItem.isPlaying
        let newIndex:Int!
        switch action {
        case .next:
            newIndex = self.currentTrackIndex < self.trackList.count - 1 ? self.currentTrackIndex + 1 : 0
        case .previous:
            newIndex = self.currentTrackIndex > 0 ? self.currentTrackIndex - 1 : self.trackList.count - 1
        }
        self.currentTrack = self.trackList[newIndex]
        currentBackNoisesItem.isPlaying = isPlaying
        NotificationCenter.default.post(name: .refreshSingleSwitchStatus, object: SwitchType.backNoises)
    }

}
