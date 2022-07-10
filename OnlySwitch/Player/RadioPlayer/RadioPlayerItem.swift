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
    {
        willSet {
            guard title != newValue else {return}
            if isPlaying &&
                !newValue.isEmpty &&
                Preferences.shared.allNotificationChangingStation {
                let _ = try? displayNotificationCMD(title: "Now Playing".localized(),
                                               content: newValue,
                                               subtitle: "")
                    .runAppleScript()
            }
        }
    }
    
    var streamUrl:String = ""
    var streamInfo:String = ""
    {
        willSet {
            guard streamInfo != newValue else {return}
            if isPlaying &&
                !newValue.isEmpty &&
                !title.isEmpty &&
                Preferences.shared.allNotificationTrack {
                let _ = try? displayNotificationCMD(title: "Now Playing".localized(),
                                               content: title,
                                               subtitle: newValue)
                    .runAppleScript()
            }
        }
    }
    
    var isEditing:Bool = false
    var id:UUID
    
    mutating func updateItem(radio:RadioStations) {
        self.id = radio.id!
        self.title = radio.title!
        self.streamUrl = radio.url!
        self.streamInfo = ""
    }
}
