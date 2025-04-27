//
//  ShowFinderPathbarSwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/1/13.
//

import Foundation
import Switches
import Defines

final class ShowFinderPathbarSwitch: SwitchProvider {
    var type: SwitchType = .showFinderPathbar
    weak var delegate: SwitchDelegate?

    @MainActor
    func currentStatus() async -> Bool {
        do {
            let result = try await ShowPathBarCMD.status.runAppleScript(isShellCMD: true)
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
                _ = try await ShowPathBarCMD.on.runAppleScript(isShellCMD: true)
            } else {
                _ = try await ShowPathBarCMD.off.runAppleScript(isShellCMD: true)
            }
        } catch {
            throw SwitchError.OperationFailed
        }
    }
    
    func isVisible() -> Bool {
        return true
    }
}
