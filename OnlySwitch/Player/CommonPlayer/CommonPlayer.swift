//
//  CommonPlayer.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/8/11.
//

import Foundation

protocol CommonPlayerItem:AnyObject {
    var isPlaying:Bool {get set}
    var title:String {get set}
    var trackInfo:String {get set}
    var url:URL? {get set}
    func nextTrack()
    func previousTrack()
}

