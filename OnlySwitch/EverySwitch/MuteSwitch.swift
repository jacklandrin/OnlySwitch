//
//  MuteSwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/1.
//

import Foundation
import AppKit


let NSVolumeKey = "NSVolumeKey"
let ASVolumeKey = "ASVolumeKey"

class MuteSwitch:SwitchProvider {
    static let shared = MuteSwitch()
    private let muteSwitchOperator:MuteSwitchProtocal = ASMuteSwitchOperator()
    
    func operationSwitch(isOn: Bool) async -> Bool {
        return muteSwitchOperator.operationSwitch(isOn: isOn)
    }
    
    func currentStatus() -> Bool {
        return muteSwitchOperator.currentStatus()
    }
    
    func isVisable() -> Bool {
        return true
    }
}

protocol MuteSwitchProtocal {
    func currentStatus() -> Bool
    func operationSwitch(isOn: Bool) -> Bool
}

class NSMuteSwitchOperator:MuteSwitchProtocal {
    func currentStatus() -> Bool {
        if NSSound.systemVolumeIsMuted {
            return true
        } else {
            let volume = NSSound.systemVolume
            UserDefaults.standard.set(volume, forKey: NSVolumeKey)
            UserDefaults.standard.synchronize()
            return false
        }
    }
    
    func operationSwitch(isOn: Bool) -> Bool {
        if isOn {
            NSSound.systemVolumeFadeToMute(seconds: 0, blocking: true)
            let isMuted = NSSound.systemVolumeIsMuted
            print("turn on, isMuted:\(isMuted)")
            return isMuted
        } else {
            var volumeValue = Float(UserDefaults.standard.float(forKey: NSVolumeKey))
            if volumeValue == 0 {
                volumeValue = 0.5
            }
            NSSound.systemVolume = volumeValue
            let isMuted = NSSound.systemVolumeIsMuted
            print("turn off, isMuted:\(isMuted)")
            return !isMuted
        }
    }
}

class ASMuteSwitchOperator:MuteSwitchProtocal {
    func currentStatus() -> Bool {
        let result = getCurrentVolume.runAppleScript()
        if result.0 {
            let volume:String = result.1 as! String
            let volumeValue:Int = Int(volume) ?? 50
            UserDefaults.standard.set(volume, forKey: ASVolumeKey)
            UserDefaults.standard.synchronize()
            return volumeValue == 0
        } else {
            return false
        }

    }
    
    func operationSwitch(isOn: Bool) -> Bool {
        if isOn {
            let cmd = setOutputVolumeCMD + "0"
            return cmd.runAppleScript().0
        } else {
            var volumeValue = UserDefaults.standard.integer(forKey: ASVolumeKey)
            volumeValue = (volumeValue == 0) ? 50 : volumeValue
            let cmd = setOutputVolumeCMD + String(volumeValue)
            return cmd.runAppleScript().0
        }

    }
}
