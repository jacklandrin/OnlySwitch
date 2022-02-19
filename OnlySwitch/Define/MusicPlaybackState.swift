//
//  MusicPlaybackState.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/2/19.
//

import Foundation
public enum MusicPlaybackState {
    case stopped
    case playing
    case paused
    case fastForwarding
    case rewinding
    case reposition
    
    var isActiveState: Bool {
        switch self {
        case .stopped, .paused:
            return false
        default:
            return true
        }
    }
}
