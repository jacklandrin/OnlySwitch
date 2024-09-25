//
//  RefreshNotification.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2024/9/22.
//
import ComposableArchitecture

extension Effect {
    static func onSwitchListChanged(perform action: @escaping @autoclosure () -> Action) -> Self {
        .publisher {
            NotificationCenter.default.publisher(for: .changeSettings)
                .map { _ in action()}
        }
    }
}
