//
//  RadioPlayerItem.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/7/6.
//

import Foundation

struct RadioPlayerItem {
    var isPlaying:Bool = false
    var title:String = ""
    var streamUrl:String = ""
    var streamInfo:String = ""
    var isEditing:Bool = false
    var id:UUID
    
    mutating func updateItem(radio:RadioStations) {
        self.id = radio.id!
        self.title = radio.title!
        self.streamUrl = radio.url!
        self.streamInfo = ""
    }
}
