//
//  LowPowerModeSwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/1/1.
//

import Foundation
import Switches
import Defines

final class LowPowerModeSwitch: SwitchProvider {
    var type: SwitchType = .lowpowerMode
    weak var delegate: SwitchDelegate?

    @MainActor
    func currentStatus() async -> Bool {
        do {
            let result = try await LowpowerModeCMD.status.runAppleScript(isShellCMD: true)
            return result.contains("1")
        } catch {
            return false
        }
    }

    @MainActor
    func currentInfo() async -> String {
        "require password"
    }

    @MainActor
    func operateSwitch(isOn: Bool) async throws {
        do {
            if isOn {
                _ = try await LowpowerModeCMD.on.runAppleScript(isShellCMD: true, with: true)
            } else {
                _ = try await LowpowerModeCMD.off.runAppleScript(isShellCMD: true, with: true)
            }
        } catch {
            throw SwitchError.OperationFailed
        }
    }
    
    func isVisible() -> Bool {
        return true
    }
}
