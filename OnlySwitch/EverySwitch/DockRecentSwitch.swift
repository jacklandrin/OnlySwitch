//
//  DockRecentSwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/1/21.
//

import Foundation
import Switches
import Defines

final class DockRecentSwitch: SwitchProvider {
    var type: SwitchType = .dockRecent
    weak var delegate: SwitchDelegate?

    @MainActor
    func currentStatus() async -> Bool {
        do {
            let result = try await ShowDockRecentCMD.status.runAppleScript(isShellCMD: true)
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
                _ = try await ShowDockRecentCMD.on.runAppleScript(isShellCMD: true)
            } else {
                _ = try await ShowDockRecentCMD.off.runAppleScript(isShellCMD: true)
            }
        } catch {
            throw SwitchError.OperationFailed
        }
        
    }
    
    func isVisible() -> Bool {
        return true
    }
    
    
}
