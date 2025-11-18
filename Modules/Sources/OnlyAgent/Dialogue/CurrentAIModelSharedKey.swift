//
//  CurrentAIModelSharedKey.swift
//  Modules
//
//  Created by Bo Liu on 18.11.25.
//

import Sharing
import Extensions
import Foundation

extension SharedKey where Self == AppStorageKey<String?>.Default {
    @available(macOS 26.0, *)
    static var currentAIModel: Self {
        Self[.appStorage(UserDefaults.Key.currentAIModel), default: nil]
    }
}
