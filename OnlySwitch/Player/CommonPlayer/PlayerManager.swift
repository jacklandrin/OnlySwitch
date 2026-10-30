//
//  File.swift
//  SpringRadio
//
//  Created by jack on 2020/4/19.
//  Copyright © 2020 jack. All rights reserved.
//

import Foundation

final class PlayerManager: @unchecked Sendable {
    static let shared = PlayerManager()
    var player:AudioPlayer!
    
    var soundWaveEffectDisplay:Bool{
        Preferences.shared.soundWaveEffectDisplay
    }
    
    init() {
        
        self.player = MainActor.assumeIsolated { HostedAudioPlayer() }
        
        if Preferences.shared.radioEnable {
            self.player.setupRemoteCommandCenter()
        }
        
        NotificationCenter.default.addObserver(forName: .soundWaveToggle, object: nil, queue: .main, using: { [self] _ in
            
            let currentPlayerItem = self.player.currentPlayerItem
            
            self.player.currentPlayerItem?.isPlaying = false
            self.player.clearCommandCenter()
            
            self.player = MainActor.assumeIsolated { HostedAudioPlayer() }
            self.player.currentPlayerItem = currentPlayerItem
            
            if Preferences.shared.radioEnable {
                self.player.setupRemoteCommandCenter()
            }
        })
    }
}
