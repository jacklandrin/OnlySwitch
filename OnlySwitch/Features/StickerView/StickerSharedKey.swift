//
//  StickerSharedKey.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 25.09.25.
//

import Foundation
import Sharing

extension SharedKey where Self == AppStorageKey<Data?>.Default {
    static var oldStickers: Self {
        Self[.appStorage(UserDefaults.Key.sticker), default: nil]
    }
}

extension SharedKey where Self == FileStorageKey<[StickerModel]?>.Default {
    @available(macOS 13.0, *)
    static var stickerCache: Self {
        let appBundleID = Bundle.main.infoDictionary?["CFBundleName"] as! String
        return Self[.fileStorage(.applicationSupportDirectory.appending(component: "\(appBundleID)/StickerCache")), default: nil]
    }
}
