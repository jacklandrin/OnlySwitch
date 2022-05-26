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
    static var production:Self {
        URLHost(rawValue: "api.github.com")
    }
}

enum EndPointKinds:String {
    case latestRelease = "repos/jacklandrin/OnlySwitch/releases/latest"
    case releases = "repos/jacklandrin/OnlySwitch/releases"
}
