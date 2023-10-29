//
//  StickerModel.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2023/10/29.
//

import Foundation

struct StickerModel: Codable {
    let content: String
    let color: String

    enum CodingKeys:String, CodingKey {
        case content
        case color
    }
}
