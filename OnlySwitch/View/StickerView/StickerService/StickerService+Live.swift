//
//  StickerService+Live.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2023/10/29.
//

import Dependencies

extension StickerService: DependencyKey {
    static var liveValue = Self(
        saveSticker: { content, color, translucent, previewMode in
            let model = StickerModel(
                content: content,
                color: color.name,
                trancelucent: translucent,
                previewMode: previewMode
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try? encoder.encode([model])
            Preferences.shared.stickerData = data
        },
        loadSticker: {
            guard let data = Preferences.shared.stickerData else {
                return (
                    content: "",
                    color: .yellow,
                    translucent: false,
                    previewMode: false
                )
            }
            
            do {
                let stickers = try JSONDecoder().decode([StickerModel].self, from: data)
                guard let sticker = stickers.first else {
                    return (
                        content: "",
                        color: .yellow,
                        translucent: false,
                        previewMode: false
                    )
                }
                return (
                    content: sticker.content,
                    color: StickerColor.generateColor(from: sticker.color),
                    translucent: sticker.trancelucent ?? false,
                    previewMode: sticker.previewMode ?? false
                )
            } catch {
                return (
                    content: "",
                    color: .yellow,
                    translucent: false,
                    previewMode: false
                )
            }
        }
    )
}
