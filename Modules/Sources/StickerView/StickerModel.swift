//
//  StickerModel.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2023/10/29.
//

import Foundation

public struct StickerModel: Equatable, Codable, Sendable {
    public let id: String?
    public let content: String
    public let color: String
    public let trancelucent: Bool?
    public let previewMode: Bool?
    public let collapseMode: Bool?
    
    public init(
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
