//
//  OpenAISharedKey.swift
//  Modules
//
//  Created by Bo Liu on 20.11.25.
//

import Extensions
import Sharing
import Foundation

extension SharedKey where Self == AppStorageKey<String>.Default {
    static var openAIAPIKey: Self {
        Self[.appStorage(UserDefaults.Key.openAIAPI), default: ""]
    }
}

extension SharedKey where Self == AppStorageKey<String>.Default {
    static var openAIHost: Self {
        Self[.appStorage(UserDefaults.Key.openAIHost), default: "api.openai.com"]
    }
}
