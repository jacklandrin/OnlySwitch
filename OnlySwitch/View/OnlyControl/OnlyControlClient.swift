//
//  OnlyControlClient.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2024/9/22.
//

import Dependencies
import DependenciesMacros

@DependencyClient
struct OnlyControlClient: Sendable {
    var fetchSwitchList: @Sendable () -> [SwitchBarVM] = { [] }
    var fetchShortcutsList: @Sendable () -> [ShortcutsBarVM] = { [] }
    var fetchEvolutionList: @Sendable () -> [EvolutionBarVM] = { [] }
}

extension OnlyControlClient: DependencyKey {
    static var testValue = Self()
    static var liveValue: Self = .live
}

extension OnlyControlClient {
    static var live: Self = .init{
        SwitchManager.shared.barVMList()
    } fetchShortcutsList: {
        SwitchManager.shared.shortcutsBarVMList()
    } fetchEvolutionList: {
        SwitchManager.shared.activeEvolutionList()
    }
}

extension DependencyValues {
    var onlyControlClient: OnlyControlClient {
        get { self[OnlyControlClient.self] }
        set { self[OnlyControlClient.self] = newValue }
    }
}
