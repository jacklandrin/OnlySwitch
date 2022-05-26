//
//  ShortcutsSettingModel.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/5/26.
//

import Foundation

struct ShortcutsSettingModel {
    var shortcutsList : [ShortcutsItem] = [ShortcutsItem]()
    var errorInfo = ""
    var showErrorToast = false
    var sharedShortcutsList:[SharedShortcutsItem] = [SharedShortcutsItem]()
}

struct ShortcutOnMarket:Codable, Identifiable {
    enum CodingKeys:CodingKey {
        case name
        case link
        case author
        case description
    }
    var id = UUID()
    var name:String
    var link:String
    var author:String
    var description: String
}
