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
        didSet {
            if isPlaying &&
                !title.isEmpty &&
                Preferences.shared.allNotificationChangingStation {
                let _ = try? displayNotificationCMD(title: "Now Playing".localized(),
                                               content: title,
                                               subtitle: "")
                    .runAppleScript()
            }
        }
    }
    var streamUrl:String = ""
    var streamInfo:String = ""
    {
        didSet {
            if isPlaying &&
                !streamInfo.isEmpty &&
                !title.isEmpty &&
                Preferences.shared.allNotificationTrack {
                let _ = try? displayNotificationCMD(title: "Now Playing".localized(),
                                               content: title,
                                               subtitle: streamInfo)
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
