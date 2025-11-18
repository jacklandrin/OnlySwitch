//
//  OllamaSharedKey.swift
//  Modules
//
//  Created by Bo Liu on 18.11.25.
//

import Extensions
import Sharing
import Foundation

extension SharedKey where Self == AppStorageKey<String>.Default {
    @available(macOS 26.0, *)
    static var ollamaUrl: Self {
        Self[.appStorage(UserDefaults.Key.ollamaUrl), default: "http://localhost:11434"]
    }
}

extension SharedKey where Self == FileStorageKey<[OllamaTag]>.Default {
    @available(macOS 26.0, *)
    static var ollamaModels: Self {
        let appBundleID = Bundle.main.infoDictionary?["CFBundleName"] as! String
        return Self[.fileStorage(.applicationSupportDirectory.appending(component: "\(appBundleID)/OllamaModels")), default: []]
    }
}
