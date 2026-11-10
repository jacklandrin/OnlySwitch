//
//  OnlyAgentLauncher.swift
//  OnlySwitch
//

import Dependencies
import DependenciesMacros
import Foundation

/// Opens the Only Agent window from Evolution settings.
@DependencyClient
struct OnlyAgentLauncher: Sendable {
    var isAvailable: @Sendable () -> Bool = { false }
    var open: @Sendable () async -> Void
}

extension OnlyAgentLauncher: DependencyKey {
    static let liveValue = Self(
        isAvailable: {
            if #available(macOS 26.0, *) { return true }
            return false
        },
        open: {
            await AICommanderSwitch.shared.present()
        }
    )

    static let testValue = Self()
    static let previewValue = Self(isAvailable: { true }, open: {})
}

extension DependencyValues {
    var onlyAgentLauncher: OnlyAgentLauncher {
        get { self[OnlyAgentLauncher.self] }
        set { self[OnlyAgentLauncher.self] = newValue }
    }
}
