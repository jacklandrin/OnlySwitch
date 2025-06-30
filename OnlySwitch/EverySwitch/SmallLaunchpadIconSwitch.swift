//
//  SmallLaunchpadIconSwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/26.
//

import Foundation
import Switches
import Defines

final class SmallLaunchpadIconSwitch: SwitchProvider {
    var type: SwitchType = .smallLaunchpadIcon
    weak var delegate: SwitchDelegate?

    @MainActor
    func currentStatus() async -> Bool {
        do {
            let result = try await SmallLaunchpadCMD.status.runAppleScript(isShellCMD: true)
            
            if (result as NSString).intValue > 5 {
                return true
            }
            return false
        } catch {
            return false
        }
        
    }

    @MainActor
    func currentInfo() -> String {
        return ""
    }

    @MainActor
    func operateSwitch(isOn: Bool) async throws {
        do {
            if isOn {
                _ = try await SmallLaunchpadCMD.on.runAppleScript(isShellCMD: true)
            } else {
                _ = try await SmallLaunchpadCMD.off.runAppleScript(isShellCMD: true)
            }
        } catch {
            throw SwitchError.OperationFailed
        }
    }
    
    func isVisible() -> Bool {
        if #available(macOS 26.0, *) {
            return false
        }
        return true
    }
}
