//
//  MuteSwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/1.
//

import Foundation

let volumeKey = "volumeKey"

class MuteSwitch:SwitchProtocal {
    static let shared = MuteSwitch()
    func operationSwitch(isOn: Bool) -> Bool {
        if isOn {
            let cmd = setOutputVolumeCMD + "0"
            return cmd.runAppleScript().0
        } else {
            let volumeValue = UserDefaults.standard.integer(forKey: volumeKey)
            let cmd = setOutputVolumeCMD + String(volumeValue)
            return cmd.runAppleScript().0
        }
    }
    
    func currentStatus() -> Bool {
        let result = getCurrentVolume.runAppleScript()
        if result.0 {
            let volume:String = result.1 as! String
            let volumeValue = Int(volume) ?? 50
            UserDefaults.standard.set(volume, forKey: volumeKey)
            UserDefaults.standard.synchronize()
            return volumeValue == 0
        } else {
            return false
        }
    }
}
