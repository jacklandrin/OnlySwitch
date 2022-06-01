//
//  ShortcutOnMarket.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/5/26.
//

import Foundation
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
