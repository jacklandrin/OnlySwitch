//
//  SpotifyPlayer.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/2/19.
//

import Foundation
import ScriptingBridge

let spotifyStateChangedNotification = NSNotification.Name("com.spotify.client.PlaybackStateChanged")

class SpotifyPlayer{
    var spotifyApp: SpotifyApplication
    var isRunning:Bool {
        spotifyApp.isRunning ?? false
    }
    weak var delegate:MusicPlayerDelegate?
    
    required init?(){
        guard let player = SBApplication(bundleIdentifier: "com.spotify.client") else {return nil}
        spotifyApp = player
        observePlayerInfoNotification()
    }
    
    deinit {
        removePlayerInfoNotification()
    }
    
    func removePlayerInfoNotification() {
        DistributedNotificationCenter.default().removeObserver(self)
    }
    
    func observePlayerInfoNotification() {
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(playerInfoChanged(_:)), name: spotifyStateChangedNotification, object: nil)
    }
    
    @objc func playerInfoChanged(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let playerState = userInfo["Player State"] as? String
        else { return }
        
        switch playerState {
        case "Paused":
            pauseEvent()
        case "Stopped":
            stoppedEvent()
        case "Playing":
            playingEvent()
        default:
            break
        }
    }

}

extension SpotifyPlayer:MusicPlayer {
    var playbackState: MusicPlaybackState {
        guard isRunning,
              let playerState = spotifyApp.playerState
        else { return .stopped }
        return MusicPlaybackState(playerState)
    }
    
    var originalPlayer: SBApplication {
        return self.spotifyApp as! SBApplication
    }
    
    func play() -> Bool {
        guard isRunning,
              let trackName = spotifyApp.currentTrack?.name,
              !trackName.isEmpty
        else { return false }
        spotifyApp.play?()
        return true
    }
    
    func pause() -> Bool {
        guard isRunning else { return false}
        spotifyApp.pause?()
        return true
    }
    
    func pauseEvent() {
        delegate?.player(self, playbackStateChanged: .paused)
    }
    
    func stoppedEvent() {
        delegate?.playerDidQuit(self)
    }
    
    func playingEvent() {
        delegate?.player(self, playbackStateChanged: .playing)
    }
}

// MARK: - Enum Extension

fileprivate extension MusicPlaybackState {
    
    init(_ playbackState: SpotifyEPlS) {
        switch playbackState {
        case .stopped:
            self = .stopped
        case .playing:
            self = .playing
        case .paused:
            self = .paused
        }
    }
}
