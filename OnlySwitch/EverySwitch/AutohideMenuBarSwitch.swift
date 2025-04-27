//
//  AutohideMenuBarSwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/8.
//

import AppKit
import Switches
import Defines

final class AutohideMenuBarSwitch: SwitchProvider {
    weak var delegate: SwitchDelegate?
    var type: SwitchType = .autohideMenuBar

    @MainActor
    func currentStatus() async -> Bool {
        do {
            let result = try await AutoHideMenuBarCMD.status.runAppleScript()
            return (result as NSString).boolValue
        } catch {
            return false
        }
        
    }

    @MainActor
    func currentInfo() async -> String {
        return ""
    }
    
    func isVisible() -> Bool {
        return true
    }

    @MainActor
    func operateSwitch(isOn: Bool) async throws {
        do {
            if isOn {
                _ = try await AutoHideMenuBarCMD.on.runAppleScript()
            } else {
                _ = try await AutoHideMenuBarCMD.off.runAppleScript()
            }
        } catch {
            throw SwitchError.OperationFailed
        }
        
    }
}
