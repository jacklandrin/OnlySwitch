//
//  DarkModeSwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/11/30.
//

import AppKit
import Switches
import Defines

final class DarkModeSwitch: SwitchProvider {
    weak var delegate: SwitchDelegate?
    var type: SwitchType = .darkMode
    
    @MainActor
    func currentStatus() async -> Bool {
        if #available(macOS 14.0, *) {
            do {
                let result = try await DarkModeCMD.status_applescript.runAppleScript()
                return result == "true" ? true : false
            } catch {
                return false
            }
        } else {
            do {
                let result = try await DarkModeCMD.status.runAppleScript(isShellCMD: true)

                if result == "Dark" {
                    return true
                } else {
                    return false
                }

            } catch {
                return false
            }
        }
    }
    
    @MainActor
    func operateSwitch(isOn: Bool) async throws {
        do {
            if isOn {
                _ = try await DarkModeCMD.on.runAppleScript()
            } else {
                _ = try await DarkModeCMD.off.runAppleScript()
            }
        } catch {
            throw SwitchError.OperationFailed
        }
    }
    
    func isVisible() -> Bool {
        return true
    }

    @MainActor
    func currentInfo() async -> String {
        return ""
    }
}
