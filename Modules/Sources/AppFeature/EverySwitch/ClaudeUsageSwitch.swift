//
//  ClaudeUsageSwitch.swift
//  OnlySwitch
//

import Defines
import Extensions
import Foundation
import Switches

/// Controls whether the Claude Usage section is shown in OnlySwitch and OnlyControl.
final class ClaudeUsageSwitch: SwitchProvider, @unchecked Sendable {
    weak var delegate: SwitchDelegate?
    let type: SwitchType = .claudeUsage

    private let visibility: @MainActor @Sendable () -> Bool
    private let setVisibility: @MainActor @Sendable (Bool) -> Void

    init(
        visibility: @escaping @MainActor @Sendable () -> Bool = {
            let defaults = UserDefaults.standard
            return defaults.object(forKey: UserDefaults.Key.showClaudeUsageTab) as? Bool ?? true
        },
        setVisibility: @escaping @MainActor @Sendable (Bool) -> Void = { isVisible in
            UserDefaults.standard.set(isVisible, forKey: UserDefaults.Key.showClaudeUsageTab)
        }
    ) {
        self.visibility = visibility
        self.setVisibility = setVisibility
    }

    @MainActor
    func currentStatus() async -> Bool {
        visibility()
    }

    @MainActor
    func currentInfo() async -> String {
        ""
    }

    @MainActor
    func operateSwitch(isOn: Bool) async throws {
        setVisibility(isOn)
        NotificationCenter.default.post(name: .changeSettings, object: nil)
    }

    func isVisible() -> Bool {
        true
    }
}
