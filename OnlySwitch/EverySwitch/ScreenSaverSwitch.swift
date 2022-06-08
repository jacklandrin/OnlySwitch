//
//  ScreenSaverSwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/3.
//

import AppKit

class ScreenSaverSwitch:SwitchProvider {
    weak var delegate: SwitchDelegate?
    var type: SwitchType = .screenSaver
    var getScreenSaverIntervalResult:String = "300"
    func operationSwitch(isOn: Bool) async throws {
        do {
            if isOn {
                var interval = UserDefaults.standard.integer(forKey: UserDefaults.Key.ScreenSaverInterval)
                interval = (interval == 0) ? 300 : interval
                let cmd = ScreenSaverCMD.on + String(interval)
                _ = try cmd.runAppleScript()
            } else {
                _ = try ScreenSaverCMD.off.runAppleScript()
            }
        } catch {
            throw SwitchError.OperationFailed
        }
        
    }
    
    func currentStatus() -> Bool {
        do {
            getScreenSaverIntervalResult = try ScreenSaverCMD.status.runAppleScript()
            let intervalStr = getScreenSaverIntervalResult
            let interval:Int = Int(intervalStr) ?? 300
            UserDefaults.standard.set(interval, forKey: UserDefaults.Key.ScreenSaverInterval)
            UserDefaults.standard.synchronize()
            return interval != 0
        } catch {
            return false
        }
        
    }
    
    func isVisable() -> Bool {
        return true
    }
    
    func currentInfo() -> String {
        let intervalStr = getScreenSaverIntervalResult
        let interval:Int = Int(intervalStr) ?? 300
        let info = "\(interval / 60) min"
        print(info)
        return info
    }
}
