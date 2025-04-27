//
//  ShowExtensionNameSwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/21.
//

import Foundation
import Switches
import Defines

final class ShowExtensionNameSwitch: SwitchProvider {
    var type: SwitchType = .showExtensionName
    weak var delegate: SwitchDelegate?

    @MainActor
    func currentStatus() async -> Bool {
        do {
            let result = try await ShowExtensionNameCMD.status.runAppleScript(isShellCMD: true)
            return (result as NSString).boolValue

        } catch {
            return false
        }
    }

    @MainActor
    func currentInfo() async -> String {
        return ""
    }

    @MainActor
    func operateSwitch(isOn: Bool) async throws {
        do {
            if isOn {
                _ = try await ShowExtensionNameCMD.on.runAppleScript(isShellCMD: true)
            } else {
                _ = try await ShowExtensionNameCMD.off.runAppleScript(isShellCMD: true)
            }
        } catch {
            throw SwitchError.OperationFailed
        }
    }
    
    func isVisible() -> Bool {
        return true
    }
}
