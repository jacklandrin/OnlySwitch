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
    var getScreenSaverIntervalResult:(Bool,Any) = (true,"")
    let ScreenSaverIntervalKey = "ScreenSaverIntervalKey"
    func operationSwitch(isOn: Bool) async -> Bool {
        if isOn {
            var interval = UserDefaults.standard.integer(forKey: ScreenSaverIntervalKey)
            interval = (interval == 0) ? 300 : interval
            let cmd = ScreenSaverCMD.on + String(interval)
            return cmd.runAppleScript().0
        } else {
            return ScreenSaverCMD.off.runAppleScript().0
        }
    }
    
    func currentStatus() -> Bool {
        getScreenSaverIntervalResult = ScreenSaverCMD.status.runAppleScript()
        if getScreenSaverIntervalResult.0 {
            let intervalStr = getScreenSaverIntervalResult.1 as! String
            let interval:Int = Int(intervalStr) ?? 300
            UserDefaults.standard.set(interval, forKey: ScreenSaverIntervalKey)
            UserDefaults.standard.synchronize()
            return interval != 0
        } else {
            return true
        }
    }
    
    func isVisable() -> Bool {
        return true
    }
    
    func currentInfo() -> String {
        let intervalStr = getScreenSaverIntervalResult.1 as! String
        let interval:Int = Int(intervalStr) ?? 300
        let info = "\(interval / 60) min"
        print(info)
        return info
    }
}
