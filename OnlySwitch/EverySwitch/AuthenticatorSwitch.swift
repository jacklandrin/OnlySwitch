//
//  AuthenticatorSwitch.swift
//  OnlySwitch
//

import Foundation
import Switches
import Defines

final class AuthenticatorSwitch: SwitchProvider {
    static let shared = AuthenticatorSwitch()

    weak var delegate: SwitchDelegate?
    var type: SwitchType = .authenticator

    private init() {}

    @MainActor
    func currentInfo() async -> String {
        let count = AuthenticatorStore.shared.accounts.count
        if count == 0 { return "No accounts" }
        if count == 1 { return "1 account" }
        return "\(count) accounts"
    }

    @MainActor
    func currentStatus() async -> Bool {
        AuthenticatorStore.shared.enabled
    }

    func isVisible() -> Bool { true }

    @MainActor
    func operateSwitch(isOn: Bool) async throws {
        AuthenticatorStore.shared.enabled = isOn
        NotificationCenter.default.post(name: .changeSettings, object: nil)
    }
}

