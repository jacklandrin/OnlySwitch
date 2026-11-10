//
//  CurrentAIModelSharedKey.swift
//  Modules
//
//  Created by Bo Liu on 18.11.25.
//

import Sharing
import Extensions
import Foundation

// Upgrade compatibility: existing users' model selection is stored at this
// exact path as JSON `{"provider": ..., "model": ...}`. Do not change the key,
// the path, `CurrentAIModel`'s property names or types, or add non-optional
// properties, otherwise upgraded users lose their selection.
extension SharedKey where Self == FileStorageKey<CurrentAIModel?>.Default {
    public static var currentAIModel: Self {
        let bundleName = Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "OnlySwitch"
        return Self[.fileStorage(CurrentAIModel.storageURL(bundleName: bundleName)), default: nil]
    }
}

public struct CurrentAIModel: Codable, Equatable, Sendable {
    let provider: String
    public let model: String

    public init(provider: String, model: String) {
        self.provider = provider
        self.model = model
    }

    /// The provider, or `nil` when the stored value names an unknown provider.
    public var modelProvider: ModelProvider? {
        ModelProvider(rawValue: provider)
    }

    static func storageURL(bundleName: String) -> URL {
        .applicationSupportDirectory.appending(component: "\(bundleName)/currentAIModel")
    }
}
