//
//  MuteMicSwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2022/1/7.
//

import Foundation

let MicVolumeKey = "MicVolumeKey"
class MuteMicSwitch:SwitchProvider {
    var type: SwitchType = .muteMicrophone
        
    func currentStatus() -> Bool {
        let result = getCurrentInputVolume.runAppleScript()
        if result.0 {
            let volume:String = result.1 as! String
            let volumeValue:Int = Int(volume) ?? 50
            UserDefaults.standard.set(volume, forKey: MicVolumeKey)
            UserDefaults.standard.synchronize()
            return volumeValue == 0
        } else {
            return false
        }
    }
    
    func currentInfo() -> String {
        return ""
    }
    
    func operationSwitch(isOn: Bool) async -> Bool {
        if isOn {
            let cmd = setInputVolumeCMD + "0"
            return cmd.runAppleScript().0
        } else {
            var volumeValue = UserDefaults.standard.integer(forKey: MicVolumeKey)
            volumeValue = (volumeValue == 0) ? 50 : volumeValue
            let cmd = setInputVolumeCMD + String(volumeValue)
            return cmd.runAppleScript().0
        }
    }
    
    func isVisable() -> Bool {
        return true
    }
    
    
}
