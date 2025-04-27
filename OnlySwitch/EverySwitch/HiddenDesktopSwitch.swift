//
//  HiddenDesktopSwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/11/30.
//

import AppKit
import Defines
import Switches

final class HiddenDesktopSwitch: SwitchProvider {
    weak var delegate: SwitchDelegate?
    
    var type: SwitchType = .hiddeDesktop

    @MainActor
    func currentStatus() async -> Bool {
        do {
            let result = try await HideDesktopCMD.status.runAppleScript(isShellCMD: true)
            
            if result == "0" {
                return true
            } else {
                return false
            }
        } catch {
            return false
        }
    }

    @MainActor
    func operateSwitch(isOn: Bool) async throws {
        do {
            if isOn {
                _ = try await HideDesktopCMD.on.runAppleScript(isShellCMD: true)
            } else {
                _ = try await HideDesktopCMD.off.runAppleScript(isShellCMD: true)
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
    
    deinit{
        print("hidden desktop switch deinit")
    }
}
