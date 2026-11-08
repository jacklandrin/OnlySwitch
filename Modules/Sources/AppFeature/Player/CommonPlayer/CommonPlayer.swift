//
//  CommonPlayer.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/8/11.
//

import Foundation

enum PlayerType {
    case Radio
    case BackNoises
}

enum ChangeTrackAction {
    case next
    case previous
}

protocol CommonPlayerItem:AnyObject {
    var isPlaying:Bool {get set}
    var title:String {get set}
    var trackInfo:String {get set}
    var url:URL? {get set}
    var type:PlayerType {get}
    func nextTrack()
    func previousTrack()
}

