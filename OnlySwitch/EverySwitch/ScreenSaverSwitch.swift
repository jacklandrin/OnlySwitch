//
//  ScreenSaverSwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/3.
//

import AppKit
import Switches
import Defines
import Extensions
import OSLog

final class ScreenSaverSwitch: SwitchProvider {
    weak var delegate: SwitchDelegate?
    var type: SwitchType = .screenSaver
    var getScreenSaverIntervalResult: String = "300"

    @MainActor
    func operateSwitch(isOn: Bool) async throws {
        do {
            if isOn {
                var interval = UserDefaults.standard.integer(forKey: UserDefaults.Key.ScreenSaverInterval)
                interval = (interval == 0) ? 300 : interval
                let cmd = ScreenSaverCMD.on + String(interval)
                _ = try await cmd.runAppleScript()
            } else {
                _ = try await ScreenSaverCMD.off.runAppleScript()
            }
        } catch {
            throw SwitchError.OperationFailed
        }
    }

    @MainActor
    func currentStatus() async -> Bool {
        do {
            getScreenSaverIntervalResult = try await ScreenSaverCMD.status.runAppleScript()
            let intervalStr = getScreenSaverIntervalResult
            let interval:Int = Int(intervalStr) ?? 300
            UserDefaults.standard.set(interval, forKey: UserDefaults.Key.ScreenSaverInterval)
            UserDefaults.standard.synchronize()
            return interval != 0
        } catch {
            return false
        }
    }
    
    func isVisible() -> Bool {
        return true
    }

    @MainActor
    func currentInfo() async -> String {
        let intervalStr = getScreenSaverIntervalResult
        let interval:Int = Int(intervalStr) ?? 300
        let info = "\(interval / 60) min"
        Logger.internalSwitch.debug("\(info)")
        return info
    }
}
