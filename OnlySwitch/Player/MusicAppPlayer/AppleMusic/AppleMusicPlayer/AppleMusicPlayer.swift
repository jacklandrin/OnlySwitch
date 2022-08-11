//
//  AppleMusicPlayer.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/2/20.
//

import Foundation
import ScriptingBridge

let appleMusicStateChangedNotification = NSNotification.Name("com.apple.Music.playerInfo")

class AppleMusicPlayer {
    weak var delegate:MusicPlayerDelegate?
    var applemusicApp:iTunesApplication
    
    required init?() {
        guard let player = SBApplication(bundleIdentifier: "com.apple.Music") else {return nil}
        applemusicApp = player
        observePlayerInfoNotification()
    }
    
    deinit {
        removePlayerInfoNotification()
    }
    
    func observePlayerInfoNotification() {
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(playerInfoChanged(_:)), name: appleMusicStateChangedNotification, object: nil)
    }
    
    func removePlayerInfoNotification() {
        DistributedNotificationCenter.default().removeObserver(self)
    }
    
    @objc func playerInfoChanged(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let playerState = userInfo["Player State"] as? String
        else { return }
        
        switch playerState {
        case "Paused":
            pauseEvent()
            print("paused")
        case "Stopped":
            stoppedEvent()
            print("stopped")
        case "Playing":
            playingEvent()
            print("playing")
        default:
            break
        }
    }
}

extension AppleMusicPlayer:MusicPlayer {
    var originalPlayer: SBApplication {
        return applemusicApp as! SBApplication
    }
    
    var playbackState: MusicPlaybackState {
        guard isRunning,
              let playerState = applemusicApp.playerState
        else { return .stopped }
        return MusicPlaybackState(playerState)
    }
    
    func play() -> Bool {
        guard isRunning,
              playbackState != .playing,
              let trackName = applemusicApp.currentTrack?.name,
              !trackName.isEmpty
        else { return false}
        
        applemusicApp.playpause?()
        return true
    }
    
    func pause() -> Bool {
        guard isRunning else {return false}
        applemusicApp.pause?()
        return true
    }
    
    func pauseEvent() {
        // Rewind and fast forward would send pause notification.
        guard playbackState == .paused else { return }
        delegate?.player(self, playbackStateChanged: .paused)
    }
    
    func stoppedEvent() {
        delegate?.player(self, playbackStateChanged: .stopped)
    }
    
    func playingEvent() {
        delegate?.player(self, playbackStateChanged: .playing)
    }
    
    
}

// MARK: - Enum Extension

fileprivate extension MusicPlaybackState {
    
    init(_ playbackState: iTunesEPlS) {
        switch playbackState {
        case .stopped:
            self = .stopped
        case .playing:
            self = .playing
        case .paused:
            self = .paused
        case .fastForwarding:
            self = .fastForwarding
        case .rewinding:
            self = .rewinding
        }
    }
}
