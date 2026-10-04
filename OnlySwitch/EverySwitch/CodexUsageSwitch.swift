//
//  CodexUsageSwitch.swift
//  OnlySwitch
//

import Defines
import Extensions
import Foundation
import Switches

/// Controls whether the Codex Usage section is shown in OnlySwitch and OnlyControl.
final class CodexUsageSwitch: SwitchProvider, @unchecked Sendable {
    weak var delegate: SwitchDelegate?
    let type: SwitchType = .codexUsage

    private let visibility: @MainActor @Sendable () -> Bool
    private let setVisibility: @MainActor @Sendable (Bool) -> Void

    init(
        visibility: @escaping @MainActor @Sendable () -> Bool = {
            let defaults = UserDefaults.standard
            return defaults.object(forKey: UserDefaults.Key.showCodexUsageTab) as? Bool ?? true
        },
        setVisibility: @escaping @MainActor @Sendable (Bool) -> Void = { isVisible in
            UserDefaults.standard.set(isVisible, forKey: UserDefaults.Key.showCodexUsageTab)
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
