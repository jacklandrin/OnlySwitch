//
//  KeyLightService.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2024/4/28.
//

import Dependencies
import Foundation

struct KeyLightService {
    var loadKeyboardManager: () -> Void
    var setBrightness: (Double) -> Void
    var brightness: () -> Double
    var setAutoBrightness: (Bool) -> Void
    var autoBrightness: () -> Bool
}

extension KeyLightService: TestDependencyKey {
    static let testValue: KeyLightService = .init(
        loadKeyboardManager: unimplemented("\(Self.self).loadKeyboardManager"),
        setBrightness: unimplemented("\(Self.self).setBrightness"),
        brightness: unimplemented("\(Self.self).brightness"),
        setAutoBrightness: unimplemented("\(Self.self).setAutoBrightness"),
        autoBrightness: unimplemented("\(Self.self).autoBrightness")
    )
}

extension DependencyValues {
    var keyLightService: KeyLightService {
        get { self[KeyLightService.self] }
        set { self[KeyLightService.self] = newValue }
    }
}
