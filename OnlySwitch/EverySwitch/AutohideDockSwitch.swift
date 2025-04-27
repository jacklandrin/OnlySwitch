//
//  AutohideDockSwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/6.
//

import AppKit
import Switches
import Defines

final class AutohideDockSwitch: SwitchProvider {
    weak var delegate: SwitchDelegate?
    var type: SwitchType = .autohideDock

    @MainActor
    func currentStatus() async -> Bool {
        do {
            let result = try await AutohideDockCMD.status.runAppleScript()
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
                _ = try await AutohideDockCMD.on.runAppleScript()
            } else {
                _ = try await AutohideDockCMD.off.runAppleScript()
            }
        } catch {
            throw SwitchError.OperationFailed
        }
    }
}
