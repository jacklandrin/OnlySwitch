//
//  SoundMixerSwitch.swift
//  OnlySwitch
//

import Defines
import Foundation
import Switches

/// Shows the sound mixer panel in the switch list, the same way ``AuthenticatorSwitch`` shows the
/// authenticator panel. The panel itself lives in the popover, so the mixer needs no menu bar item
/// of its own.
final class SoundMixerSwitch: SwitchProvider, @unchecked Sendable {
    @MainActor static let shared = SoundMixerSwitch()

    weak var delegate: SwitchDelegate?
    var type: SwitchType = .soundMixer

    private init() {}

    @MainActor
    func currentInfo() async -> String {
        let count = SoundMixerVM.shared.rows.count
        guard SoundMixerVM.shared.enabled, count > 0 else { return "" }
        return count == 1 ? "1 app".localized()
                          : String(format: "%lld apps".localized(), count)
    }

    @MainActor
    func currentStatus() async -> Bool {
        SoundMixerVM.shared.enabled
    }

    func isVisible() -> Bool { true }

    @MainActor
    func operateSwitch(isOn: Bool) async throws {
        SoundMixerVM.shared.enabled = isOn
        NotificationCenter.default.post(name: .changeSettings, object: nil)
    }
}
