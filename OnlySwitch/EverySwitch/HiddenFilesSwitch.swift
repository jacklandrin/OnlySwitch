//
//  HiddenFilesSwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/8.
//

import AppKit
import Switches
import Defines

final class HiddenFilesSwitch: SwitchProvider {
    weak var delegate: SwitchDelegate?
    var type: SwitchType = .hiddenFiles

    @MainActor
    func currentInfo() async -> String {
        return ""
    }

    @MainActor
    func currentStatus() async -> Bool {
        do {
            let result = try await ShowHiddenFilesCMD.status.runAppleScript(isShellCMD: true)
            return (result as NSString).boolValue
        } catch {
            return false
        }
        
    }
    
    func isVisible() -> Bool {
        return true
    }

    @MainActor
    func operateSwitch(isOn: Bool) async throws {
        do {
            if isOn {
                _ = try await ShowHiddenFilesCMD.on.runAppleScript(isShellCMD: true)
            } else {
                _ = try await ShowHiddenFilesCMD.off.runAppleScript(isShellCMD: true)
            }
        } catch {
            throw SwitchError.OperationFailed
        }
        
    }
}
