//
//  CBTrueToneClient++.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2023/10/27.
//

import Foundation
import OnlySwitchObjC

extension CBTrueToneClient: @unchecked Sendable {}

extension CBTrueToneClient {
    static let shared = CBTrueToneClient()

    var isTrueToneSupported: Bool {
        supported()
    }

    var isTrueToneAvailable: Bool {
        available()
    }

    var isTrueToneEnabled: Bool {
        get {
            enabled()
        }
        set {
            setEnabled(newValue)
        }
    }
}
