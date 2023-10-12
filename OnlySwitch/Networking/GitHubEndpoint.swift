//
//  GitHubEndpoint.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/5/26.
//

import Foundation

let httpsScheme = "https"

struct URLHost:RawRepresentable {
    var rawValue: String
}

extension URLHost {
    static var gitHubAPI:Self {
        URLHost(rawValue: "api.github.com")
    }
    
    static var userContent:Self {
        URLHost(rawValue: "raw.githubusercontent.com")
    }
}

enum EndPointKinds:String {
    case latestRelease = "repos/jacklandrin/OnlySwitch/releases/latest"
    case releases = "repos/jacklandrin/OnlySwitch/releases"
    case shortcutsJson = "jacklandrin/OnlySwitch/main/OnlySwitch/Resource/ShortcutsMarket/ShortcutsMarket.json"
    case evolutionJson = "jacklandrin/OnlySwitch/main/OnlySwitch/Resource/Evolution/EvolutionMarket.json"
}
