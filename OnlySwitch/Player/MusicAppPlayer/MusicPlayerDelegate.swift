//
//  MusicPlayerDelegate.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/2/19.
//

import Foundation
protocol MusicPlayerDelegate: AnyObject {
    
    /// Tells the delegate the player's playback state has been changed.
    ///
    /// - Parameters:
    ///   - player: The player which triggers this event.
    ///   - position: Player position.
    func player(_ player: MusicPlayer, playbackStateChanged playbackState: MusicPlaybackState)
    
    
    /// Tells the delegate the player has quitted.
    ///
    /// - Parameter player: The player which triggers this event.
    func playerDidQuit(_ player: MusicPlayer)
}
