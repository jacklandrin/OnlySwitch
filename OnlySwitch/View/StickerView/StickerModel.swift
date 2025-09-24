//
//  StickerModel.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2023/10/29.
//

import Foundation

struct StickerModel: Equatable, Codable {
    let id: String?
    let content: String
    let color: String
    let trancelucent: Bool?
    let previewMode: Bool?
    let collapseMode: Bool?
    
    init(
        id: String = UUID().uuidString,
        content: String = "",
        color: String = "yellow",
        trancelucent: Bool = false,
        previewMode: Bool = false,
        collapseMode: Bool = false
    ) {
        self.id = id
        self.content = content
        self.color = color
        self.trancelucent = trancelucent
        self.previewMode = previewMode
        self.collapseMode = collapseMode
    }
}
