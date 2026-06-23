//
//  ClaudeSharedKey.swift
//  Modules
//
//  Created by Louis Saks on 23.06.26.
//

import Extensions
import Sharing
import Foundation

extension SharedKey where Self == KeychainStorageKey<String>.Default {
    static var claudeAPIKey: Self {
        let service = Bundle.main.bundleIdentifier ?? "jacklandrin.OnlySwitch"
        return .keychainStorage(key: UserDefaults.Key.claudeAPI, defaultValue: "", service: service)
    }
}
