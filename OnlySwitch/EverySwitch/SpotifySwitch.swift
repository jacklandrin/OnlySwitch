//
//  SpotifySwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/2/19.
//

import Foundation

class SpotifySwitch: SwitchProvider, MusicPlayerDelegate {
    
    static let shared = SpotifySwitch()
    
    weak var delegate: SwitchDelegate?
    
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
    
    func operateSwitch(isOn: Bool) async throws {
        guard let player = player else {
            throw SwitchError.OperationFailed
        }
        var success = false
        if isOn {
            success = player.play()
        } else {
            success = player.pause()
        }
        if !success {
            throw SwitchError.OperationFailed
        }
    }
    
    func isVisible() -> Bool {
        //for Spotify installation after Only Switch launched
        if player == nil {
            player = SpotifyPlayer()
        }
        guard let player = player else {
            return false
        }

        return player.isRunning
    }
    
    // MARK: - MusicPlayerDelegate
    func player(_ player: MusicPlayer, playbackStateChanged playbackState: MusicPlaybackState) {
        guard player === self.player else {return}
        self.state = playbackState
        self.delegate?.shouldRefreshIfNeed(aSwitch: self)
    }
    
    func playerDidQuit(_ player: MusicPlayer) {
        guard player === self.player else {return}
        self.state = .stopped
        self.delegate?.shouldRefreshIfNeed(aSwitch: self)
    }
    
    
}
