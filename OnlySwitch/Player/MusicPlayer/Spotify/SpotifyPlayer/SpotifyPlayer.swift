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
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(playerInfoChanged(_:)), name: spotifyStateChangedNotification, object: nil)
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
    
    func play() -> Bool {
        guard isRunning else { return false}
        spotifyApp.play?()
        return true
    }
    
    func pause() -> Bool {
        guard isRunning else { return false}
        spotifyApp.pause?()
        return true
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
