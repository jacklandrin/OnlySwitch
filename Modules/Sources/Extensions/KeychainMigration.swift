//
//  KeychainMigration.swift
//  Modules
//
//  Created by Bo Liu on 06.12.25.
//

import Foundation

public enum KeychainMigration {
    /// Migrates API keys from UserDefaults to Keychain if they exist
    public static func migrateAPIKeysIfNeeded() {
        let service = Bundle.main.bundleIdentifier ?? "jacklandrin.OnlySwitch"
        let keychain = KeychainManager(service: service)
        
        // Migrate OpenAI API Key
        if let openAIKey = UserDefaults.standard.string(forKey: UserDefaults.Key.openAIAPI),
           !openAIKey.isEmpty {
            // Check if already in Keychain
            let apiInKeychain = (try? keychain.retrieve(key: UserDefaults.Key.openAIAPI)) ?? ""
            
            if apiInKeychain.isEmpty {
                // Not in Keychain, migrate it
                try? keychain.save(key: UserDefaults.Key.openAIAPI, value: openAIKey)
                // Optionally remove from UserDefaults after migration
                // UserDefaults.standard.removeObject(forKey: UserDefaults.Key.openAIAPI)
            }
        }
    }
}

