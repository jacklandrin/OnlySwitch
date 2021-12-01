//
//  MuteSwitch.swift
//  OnlySwitch
//
//  Created by Jacklandrin on 2021/12/1.
//

import Foundation
import AppKit


let volumeKey = "volumeKey"

class MuteSwitch:SwitchProtocal {
    static let shared = MuteSwitch()
    
    func operationSwitch(isOn: Bool) -> Bool {
        if isOn {
            NSSound.systemVolumeFadeToMute(seconds: 0, blocking: true)
            let isMuted = NSSound.systemVolumeIsMuted
            print("turn on, isMuted:\(isMuted)")
            return isMuted
        } else {
            var volumeValue = Float(UserDefaults.standard.float(forKey: volumeKey))
            if volumeValue == 0 {
                volumeValue = 0.5
            }
            NSSound.systemVolume = volumeValue
            let isMuted = NSSound.systemVolumeIsMuted
            print("turn off, isMuted:\(isMuted)")
            return !isMuted
        }
    }
    
    func currentStatus() -> Bool {
        if NSSound.systemVolumeIsMuted {
            return true
        } else {
            let volume = NSSound.systemVolume
            UserDefaults.standard.set(volume, forKey: volumeKey)
            UserDefaults.standard.synchronize()
            return false
        }
        
    }
}
