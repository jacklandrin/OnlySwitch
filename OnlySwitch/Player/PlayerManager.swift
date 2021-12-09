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
}
