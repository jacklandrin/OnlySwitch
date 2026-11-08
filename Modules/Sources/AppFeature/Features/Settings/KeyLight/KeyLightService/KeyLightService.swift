//
//  KeyLightService.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2024/4/28.
//

import Dependencies
import DependenciesMacros
import Foundation

@DependencyClient
struct KeyLightService: Sendable {
    var loadKeyboardManager: @Sendable () -> Void
    var setBrightness: @Sendable (Double) -> Void
    var brightness: @Sendable () -> Double = { 0.0 }
    var setAutoBrightness: @Sendable (Bool) -> Void
    var autoBrightness: @Sendable () -> Bool = { false }
}

extension KeyLightService: TestDependencyKey {
    static let testValue: KeyLightService = Self()
}

extension DependencyValues {
    var keyLightService: KeyLightService {
        get { self[KeyLightService.self] }
        set { self[KeyLightService.self] = newValue }
    }
}
