//
//  OpenAISharedKey.swift
//  Modules
//
//  Created by Bo Liu on 20.11.25.
//

import Extensions
import Sharing
import Foundation

extension SharedKey where Self == KeychainStorageKey<String>.Default {
    static var openAIAPIKey: Self {
        let service = Bundle.main.bundleIdentifier ?? "jacklandrin.OnlySwitch"
        return .keychainStorage(key: UserDefaults.Key.openAIAPI, defaultValue: "", service: service)
    }
}

extension SharedKey where Self == AppStorageKey<String>.Default {
    static var openAIHost: Self {
        Self[.appStorage(UserDefaults.Key.openAIHost), default: "api.openai.com"]
    }
}
