//
//  RadioStationSwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/9.
//

import Foundation

class RadioStationSwitch:SwitchProvider {
    static let shared = RadioStationSwitch()
    var playerItem:RadioPlayerItem = RadioPlayerItem(isPlaying: false, title: "Country Radio", streamUrl: "http://uk2.internet-radio.com:8024/stream", streamInfo: "")
    func operationSwitch(isOn: Bool) async -> Bool {
        if isOn {
            playerItem.isPlaying = PlayerManager.shared.player.play(stream: playerItem)
            return playerItem.isPlaying
        } else {
            PlayerManager.shared.player.stop()
            playerItem.isPlaying = false
            playerItem.streamInfo = ""
            return true
        }
    }
    
    func currentStatus() -> Bool {
        return playerItem.isPlaying
    }
    
    func currentInfo() -> String {
        return playerItem.title
    }
    
    func isVisable() -> Bool {
        return true
    }
}
