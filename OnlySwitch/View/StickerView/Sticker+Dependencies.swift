//
//  Sticker+Dependencies.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2023/10/29.
//

import Dependencies

extension DependencyValues {
    var stickerService: StickerService {
        get { self[StickerService.self] }
        set { self[StickerService.self] = newValue }
    }
}
