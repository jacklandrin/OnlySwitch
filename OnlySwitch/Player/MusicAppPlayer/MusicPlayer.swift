//
//  MusicPlayer.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/2/20.
//

import Foundation
import ScriptingBridge

protocol MusicPlayer:AnyObject {
    /// get music player stutas changed from outside.
    var delegate:MusicPlayerDelegate? {get set}
    /// The original ScritingBridge player of the MusicPlayer instance.
    var originalPlayer: SBApplication { get }
    /// Make the player play.
    func play() -> Bool
    /// Pause the player.
    func pause() -> Bool
    /// The playback state of the player.
    var playbackState: MusicPlaybackState { get }
    
    func pauseEvent()
    func stoppedEvent()
    func playingEvent()
}

// Application Control
extension MusicPlayer {
    
    /// Check whether the player is running.
    public var isRunning: Bool {
        return originalPlayer.isRunning
    }
    
    /// Activate the player from background or killed state.
    public func activate() {
        originalPlayer.activate()
    }
}
