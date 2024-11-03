//
//  RefreshNotification.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2024/9/22.
//
import ComposableArchitecture
import Switches

extension Effect {
    static func onSwitchListChanged(perform action: @escaping @autoclosure () -> Action) -> Self {
        .publisher {
            NotificationCenter.default.publisher(for: .changeSettings)
                .map { _ in action()}
        }
    }

    static func singleItemChanged(perform action: @escaping (SwitchType) -> Action) -> Self {
        .publisher {
            NotificationCenter.default.publisher(for: .refreshSingleSwitchStatus)
                .compactMap {
                    if let type = $0.object as? SwitchType {
                        return action(type)
                    } else {
                        return nil
                    }
                }
        }
    }
}
