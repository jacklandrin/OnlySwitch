//
//  AppleMusicPlayer.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/2/20.
//

import Foundation
import ScriptingBridge
import OSLog
import Extensions

let appleMusicStateChangedNotification = NSNotification.Name("com.apple.Music.playerInfo")

class AppleMusicPlayer {
    weak var delegate:MusicPlayerDelegate?
    /// Track from the last playback notification, readable without Automation permission.
    private(set) var notifiedTrack: (name: String?, artist: String?)?
    var applemusicApp:iTunesApplication
    
    required init?() {
        guard let player = SBApplication(bundleIdentifier: "com.apple.Music") else {return nil}
        applemusicApp = player
        observePlayerInfoNotification()
    }
    
    deinit {
        removePlayerInfoNotification()
    }
    
    /// AppKit suspends distributed notifications while the app is inactive, which a menu bar app
    /// almost always is, so deliver immediately to keep the cached state current.
    func observePlayerInfoNotification() {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(playerInfoChanged(_:)),
            name: appleMusicStateChangedNotification,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
    }
    
    func removePlayerInfoNotification() {
        DistributedNotificationCenter.default().removeObserver(self)
    }
    
    @objc func playerInfoChanged(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let playerState = userInfo["Player State"] as? String
        else { return }
        notifiedTrack = playerState == "Stopped"
            ? nil
            : (userInfo["Name"] as? String, userInfo["Artist"] as? String)
        
        switch playerState {
        case "Paused":
            pauseEvent()
            Logger.player.debug("paused")
        case "Stopped":
            stoppedEvent()
            Logger.player.debug("stopped")
        case "Playing":
            playingEvent()
            Logger.player.debug("playing")
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
        // A player that quits mid-request replies with no state, which is not a valid case
        // and would trap when switched on, so validate it through its raw value first.
        guard isRunning,
              let rawState = applemusicApp.playerState?.rawValue,
              let playerState = iTunesEPlS(rawValue: rawState)
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
    
    @MainActor
    func nextTrack() {
        // Paused players can skip too, and the playing state can lag behind a background player.
        guard isRunning else { return }
        applemusicApp.nextTrack?()
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
