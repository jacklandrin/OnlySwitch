//
//  MuteMicSwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/1/7.
//

import Foundation
import Switches
import Defines

final class MuteMicSwitch: SwitchProvider {
    var type: SwitchType = .muteMicrophone
    weak var delegate: SwitchDelegate?

    @MainActor
    func currentStatus() async -> Bool {
        do {
            let volume = try await VolumeCMD.getInput.runAppleScript()
            let volumeValue:Int = Int(volume) ?? 50
            UserDefaults.standard.set(volume, forKey: UserDefaults.Key.MicVolume)
            UserDefaults.standard.synchronize()
            return volumeValue == 0
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
                let cmd = VolumeCMD.setInput + "0"
                _ = try await cmd.runAppleScript()
            } else {
                var volumeValue = UserDefaults.standard.integer(forKey: UserDefaults.Key.MicVolume)
                volumeValue = (volumeValue == 0) ? 50 : volumeValue
                let cmd = VolumeCMD.setInput + String(volumeValue)
                _ = try await cmd.runAppleScript()
            }
        } catch {
            throw SwitchError.OperationFailed
        }
    }
    
    func isVisible() -> Bool {
        return true
    }
}
