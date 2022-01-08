//
//  File.swift
//  SpringRadio
//
//  Created by jack on 2020/4/19.
//  Copyright © 2020 jack. All rights reserved.
//

import Foundation

class PlayerManager {
    static let shared = PlayerManager()
    var player:AudioPlayer = JLASAudioPlayer()
    @UserDefaultValue(key: soundWaveEffectDisplayKey, defaultValue: true)
    var soundWaveEffectDisplay:Bool
    init() {
        NotificationCenter.default.addObserver(forName: soundWaveToggleNotification, object: nil, queue: .main, using: { [self] _ in
          
            self.player.currentAudioStation?.isPlaying = false
             
            if soundWaveEffectDisplay {
                self.player = JLASAudioPlayer()
            } else {
                self.player = JLAVAudioPlayer()
            }

        })
    }
}
