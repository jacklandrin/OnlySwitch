//
//  GeminiSharedKey.swift
//  Modules
//
//  Created by Bo Liu on 06.12.25.
//

import Extensions
import Sharing
import Foundation

extension SharedKey where Self == AppStorageKey<String>.Default {
    static var geminiAPIKey: Self {
        Self[.appStorage(UserDefaults.Key.geminiAPI), default: ""]
    }
}

