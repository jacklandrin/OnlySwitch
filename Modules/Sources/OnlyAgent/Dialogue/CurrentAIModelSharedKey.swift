//
//  CurrentAIModelSharedKey.swift
//  Modules
//
//  Created by Bo Liu on 18.11.25.
//

import Sharing
import Extensions
import Foundation

extension SharedKey where Self == FileStorageKey<CurrentAIModel?>.Default {
    @available(macOS 26.0, *)
    public static var currentAIModel: Self {
        let appBundleID = Bundle.main.infoDictionary?["CFBundleName"] as! String
        return Self[.fileStorage(.applicationSupportDirectory.appending(component: "\(appBundleID)/currentAIModel")), default: nil]
    }
}

public struct CurrentAIModel: Codable, Equatable {
    let provider: String
    public let model: String
}
