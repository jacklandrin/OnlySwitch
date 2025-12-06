//
//  GeminiSharedKey.swift
//  Modules
//
//  Created by Bo Liu on 06.12.25.
//

import Extensions
import Sharing
import Foundation

extension SharedKey where Self == KeychainStorageKey<String>.Default {
    static var geminiAPIKey: Self {
        let service = Bundle.main.bundleIdentifier ?? "jacklandrin.OnlySwitch"
        return .keychainStorage(key: UserDefaults.Key.geminiAPI, defaultValue: "", service: service)
    }
}

