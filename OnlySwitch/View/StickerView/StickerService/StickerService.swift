//
//  StickerService.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2023/10/29.
//

import Foundation

struct StickerService {
    var saveSticker: (_ content: String, _ color: StickerColor, _ translucent: Bool) -> Void
    var loadSticker: () -> (content: String, color: StickerColor, translucent: Bool)
}
