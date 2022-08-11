//
//  BackNoisesPlayerItem.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/8/11.
//

import Foundation
struct BackNoisesPlayerItem {
    var isPlaying: Bool = false
    
    var track: BackNoisesTrackManager.Tracks = .WhiteNoise
    
    var trackInfo: String = ""
    
    var url: URL?
}
