//
//  BackNoisesPlayer.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/8/11.
//

import Foundation


class BackNoisesPlayerItemViewModel: CommonPlayerItem,
                                ObservableObject,
                                Identifiable {
    private let player: () -> AudioPlayer

    init(player: @escaping () -> AudioPlayer = { PlayerManager.shared.player }) {
        self.player = player
    }
    
    var changeToNextTrack:(() -> Void)?
    var changeToPreviousTrack:(() -> Void)?
    
    @Published private var model = BackNoisesPlayerItem()
    var isPlaying: Bool {
        get {
            return model.isPlaying
        }
        set {
            self.model.isPlaying = newValue
            if newValue, model.url != nil {
                player().play(stream: self)
            } else if !newValue, player().currentPlayerItem === self {
                player().stop()
            }
        }
    }
    
    var title: String {
        get {
            return model.track.rawValue
        }
        set {
            model.track = BackNoisesTrackManager.Tracks(rawValue: newValue) ?? .WhiteNoise
        }
    }
    
    var track: BackNoisesTrackManager.Tracks {
        get {
            return model.track
        }
        
        set {
            model.track = newValue
        }
    }
    
    var trackInfo: String {
        get {
            return model.trackInfo
        }
        set {
            model.trackInfo = newValue
        }
    }
    
    var url: URL? {
        get {
            return model.url
        }
        
        set {
            model.url = newValue
        }
    }
    
    var type: PlayerType = .BackNoises
    
    func nextTrack() {
        guard let changeToNextTrack = changeToNextTrack else {
            return
        }
        changeToNextTrack()
    }
    
    func previousTrack() {
        guard let changeToPreviousTrack = changeToPreviousTrack else {
            return
        }
        
        changeToPreviousTrack()
    }
    
    
}
