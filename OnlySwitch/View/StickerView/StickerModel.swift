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
    let trancelucent: Bool?
    let previewMode: Bool?

    enum CodingKeys:String, CodingKey {
        case content
        case color
        case trancelucent
        case previewMode
    }
}
