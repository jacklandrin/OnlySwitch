//
//  SpotifySwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/2/19.
//

import Foundation

class SpotifySwitch: SwitchProvider, MusicPlayerDelegate {

    var delegate: SwitchDelegate?
    
    var type: SwitchType = .spotify
    var player = SpotifyPlayer()
    
    var state:MusicPlaybackState = .stopped
    
    init() {
        player?.delegate = self
    }
    
    func currentStatus() -> Bool {
        guard let _ = player else {
            return false
        }
        return state.isActiveState
    }
    
    func currentInfo() -> String {
        return ""
    }
    
    func operationSwitch(isOn: Bool) async -> Bool {
        guard let player = player else {
            return false
        }
        if isOn {
            return player.play()
        } else {
            return player.pause()
        }
    }
    
    func isVisable() -> Bool {
        guard let _ = player else {return false}
        return true
    }
    
    // Mark: - MusicPlayerDelegate
    func player(_ player: SpotifyPlayer, playbackStateChanged playbackState: MusicPlaybackState) {
        guard player === self.player else {return}
        self.state = playbackState
        self.delegate?.shouldRefreshIfNeed()
    }
    
    func playerDidQuit(_ player: SpotifyPlayer) {
        guard player === self.player else {return}
        self.state = .stopped
        self.delegate?.shouldRefreshIfNeed()
    }
    
    
}
